#import <dlfcn.h>
#if __has_feature(ptrauth_calls)
#import <ptrauth.h>
#endif
#import <mach/mach.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <mach-o/nlist.h>
#import <string.h>
#import "SGRebind.h"
#import "SGLog.h"

static const struct mach_header_64 *mainExecutable(intptr_t *slide) {
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const struct mach_header *header = _dyld_get_image_header(i);
        if (header->magic != MH_MAGIC_64 || header->filetype != MH_EXECUTE) continue;
        *slide = _dyld_get_image_vmaddr_slide(i);
        return (const struct mach_header_64 *)header;
    }
    return NULL;
}

// What protection the page holding `address` has now and at most, for the log when a write is refused.
static NSString *protectionOf(vm_address_t address) {
    vm_address_t region = address;
    vm_size_t size = 0;
    vm_region_basic_info_data_64_t info;
    mach_msg_type_number_t count = VM_REGION_BASIC_INFO_COUNT_64;
    mach_port_t object = MACH_PORT_NULL;
    if (vm_region_64(mach_task_self(), &region, &size, VM_REGION_BASIC_INFO_64, (vm_region_info_t)&info, &count, &object) != KERN_SUCCESS) return @"unknown";
    return [NSString stringWithFormat:@"now %d, at most %d, shared %d", info.protection, info.max_protection, info.shared];
}

// Writes one pointer, making its page writable first; a page dyld made read only after binding
// (__DATA_CONST, __AUTH_CONST) is copied and made read only again. Where that is refused, the page is made writable
// without the copy; failing that, the slot is left as it is. On an iPhone 11 with a jailbreak (iOS 17.5.1) both were
// refused (KERN_PROTECTION_FAILURE on a page read only now and readable and writable at most), and the page must not
// be replaced instead: a copy of it mapped over it with vm_remap left the range with no mapping at all, and Spotify
// died of SIGBUS at launch (the phone, 2026-10-23).
static BOOL writeSlot(void **slot, void *value, BOOL readOnly) {
    vm_size_t page = vm_page_size;
    vm_address_t start = (vm_address_t)slot & ~(page - 1);
    kern_return_t result = vm_protect(mach_task_self(), start, page, FALSE, VM_PROT_READ | VM_PROT_WRITE | VM_PROT_COPY);
    if (result != KERN_SUCCESS) result = vm_protect(mach_task_self(), start, page, FALSE, VM_PROT_READ | VM_PROT_WRITE);
    if (result != KERN_SUCCESS) {
        static int logged;
        if (logged++ < 3) SGLog(@"rebind: vm_protect failed (%d), the page %@", result, protectionOf(start));
        return NO;
    }
    *slot = value;
    if (readOnly) vm_protect(mach_task_self(), start, page, FALSE, VM_PROT_READ);
    return YES;
}

BOOL SGRebindImport(const char *symbol, void *replacement, void **original) {
    intptr_t slide = 0;
    const struct mach_header_64 *header = mainExecutable(&slide);
    if (!header) return NO;

    const struct segment_command_64 *linkedit = NULL;
    const struct symtab_command *symtab = NULL;
    const struct dysymtab_command *dysymtab = NULL;
    const struct load_command *command = (const struct load_command *)(header + 1);
    for (uint32_t i = 0; i < header->ncmds; i++, command = (const struct load_command *)((const char *)command + command->cmdsize)) {
        if (command->cmd == LC_SEGMENT_64 && strcmp(((const struct segment_command_64 *)command)->segname, SEG_LINKEDIT) == 0) {
            linkedit = (const struct segment_command_64 *)command;
        } else if (command->cmd == LC_SYMTAB) {
            symtab = (const struct symtab_command *)command;
        } else if (command->cmd == LC_DYSYMTAB) {
            dysymtab = (const struct dysymtab_command *)command;
        }
    }
    if (!linkedit || !symtab || !dysymtab || !dysymtab->nindirectsyms) return NO;

    uintptr_t base = (uintptr_t)slide + (uintptr_t)(linkedit->vmaddr - linkedit->fileoff);
    const struct nlist_64 *symbols = (const struct nlist_64 *)(base + symtab->symoff);
    const char *strings = (const char *)(base + symtab->stroff);
    const uint32_t *indirect = (const uint32_t *)(base + dysymtab->indirectsymoff);

    // The symbol's index once, among the undefined ones, rather than a name compared per slot.
    uint32_t wanted = UINT32_MAX;
    for (uint32_t i = dysymtab->iundefsym; i < dysymtab->iundefsym + dysymtab->nundefsym && i < symtab->nsyms; i++) {
        uint32_t offset = symbols[i].n_un.n_strx;
        if (offset >= symtab->strsize) continue;
        const char *name = strings + offset;
        if (name[0] == '_' && strcmp(name + 1, symbol) == 0) {
            wanted = i;
            break;
        }
    }
    if (wanted == UINT32_MAX) return NO;

    BOOL rebound = NO;
    command = (const struct load_command *)(header + 1);
    for (uint32_t i = 0; i < header->ncmds; i++, command = (const struct load_command *)((const char *)command + command->cmdsize)) {
        if (command->cmd != LC_SEGMENT_64) continue;
        const struct segment_command_64 *segment = (const struct segment_command_64 *)command;
        BOOL readOnly = strcmp(segment->segname, "__DATA_CONST") == 0 || strcmp(segment->segname, "__AUTH_CONST") == 0;
        const struct section_64 *section = (const struct section_64 *)(segment + 1);
        for (uint32_t s = 0; s < segment->nsects; s++, section++) {
            uint32_t type = section->flags & SECTION_TYPE;
            if (type != S_NON_LAZY_SYMBOL_POINTERS && type != S_LAZY_SYMBOL_POINTERS) continue;
            void **slots = (void **)((uintptr_t)slide + section->addr);
            uint64_t count = section->size / sizeof(void *);
            for (uint64_t k = 0; k < count; k++) {
                uint64_t entry = (uint64_t)section->reserved1 + k;
                if (entry >= dysymtab->nindirectsyms || indirect[entry] != wanted) continue;
                if (slots[k] == replacement) continue;
                void *held = slots[k];
                if (!writeSlot(&slots[k], replacement, readOnly)) continue;
                if (original && !*original) *original = held;
                rebound = YES;
            }
        }
    }
    return rebound;
}

#pragma mark - the jailbreak's hooker

typedef void (*SGMSHookFunction)(void *symbol, void *replace, void **result);

// MSHookFunction as the process has it, or from ElleKit's libraries where a rootless or a rootful jailbreak keeps them.
static SGMSHookFunction hooker(void) {
    static SGMSHookFunction found;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        found = (SGMSHookFunction)dlsym(RTLD_DEFAULT, "MSHookFunction");
        const char *paths[] = {"/var/jb/usr/lib/libellekit.dylib", "/var/jb/usr/lib/libsubstrate.dylib",
                               "/usr/lib/libellekit.dylib", "/usr/lib/libsubstrate.dylib"};
        for (size_t i = 0; !found && i < sizeof paths / sizeof *paths; i++) {
            if (access(paths[i], R_OK) != 0) continue;
            void *handle = dlopen(paths[i], RTLD_NOW);
            if (handle) found = (SGMSHookFunction)dlsym(handle, "MSHookFunction");
        }
        SGLog(@"rebind: the jailbreak's MSHookFunction %@", found ? @"is there" : @"is not there");
    });
    return found;
}

BOOL SGHookFunctionInline(void *function, void *replacement, void **original) {
    if (@available(iOS 26.0, *)) return NO;
    SGMSHookFunction hook = hooker();
    if (!hook || !function || !replacement) return NO;
    void *held = NULL;
    hook(function, replacement, &held);
    if (!held) return NO;
    if (original) *original = held;
    return YES;
}

BOOL SGCalledFromMainExecutable(void *returnAddress) {
    static uintptr_t start, end;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        intptr_t slide = 0;
        const struct mach_header_64 *header = mainExecutable(&slide);
        const struct load_command *command = header ? (const struct load_command *)(header + 1) : NULL;
        for (uint32_t i = 0; header && i < header->ncmds; i++, command = (const struct load_command *)((const char *)command + command->cmdsize)) {
            if (command->cmd != LC_SEGMENT_64 || strcmp(((const struct segment_command_64 *)command)->segname, SEG_TEXT) != 0) continue;
            const struct segment_command_64 *text = (const struct segment_command_64 *)command;
            start = (uintptr_t)slide + (uintptr_t)text->vmaddr;
            end = start + (uintptr_t)text->vmsize;
        }
    });
    // A return address carries a pointer authentication code in its top bits on arm64e.
#if __has_feature(ptrauth_calls)
    returnAddress = ptrauth_strip(returnAddress, ptrauth_key_return_address);
#endif
    uintptr_t address = (uintptr_t)returnAddress;
    return address >= start && address < end;
}
