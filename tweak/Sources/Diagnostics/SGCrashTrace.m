// A crash's stack for FLEX builds, where iOS writes none: on a jailbroken iPhone 11 the kernel answered every crash
// with "Corpse failure, too many 6" and no report reached the phone (2026-10-23). On SIGSEGV, SIGBUS, SIGILL, SIGTRAP
// and SIGABRT the faulting thread's frames are walked from its registers by their frame pointers and written to a file
// in Caches, each as image + offset; the next launch logs the file and removes it. The handler runs on a stack of its
// own for the main thread, so a stack overflow (a recursion) is caught too, and hands the signal on to the handler
// that was there before (Spotify's Crashlytics) or to the default.
//
// Threading: installed on the main thread; the handler only writes to a descriptor and reads dladdr.
#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <fcntl.h>
#import <signal.h>
#import <unistd.h>
#import <sys/ucontext.h>
#import <mach/mach.h>
#if __has_feature(ptrauth_calls)
#import <ptrauth.h>
#endif
#import "Core/SGCore.h"

#if SG_DRIVER

static char sg_path[1024];
static const int kSignals[] = {SIGSEGV, SIGBUS, SIGILL, SIGTRAP, SIGABRT};
enum { kSignalCount = sizeof kSignals / sizeof *kSignals, kMaxFrames = 96 };
static struct sigaction sg_previous[kSignalCount];

static void put(int fd, const char *text) {
    size_t length = 0;
    while (text[length]) length++;
    if (length) (void)write(fd, text, length);
}

static void putHex(int fd, uintptr_t value) {
    char digits[19] = "0x";
    int n = 0;
    char reversed[16];
    do {
        reversed[n++] = "0123456789abcdef"[value & 15];
        value >>= 4;
    } while (value && n < 16);
    for (int i = 0; i < n; i++) digits[2 + i] = reversed[n - 1 - i];
    digits[2 + n] = 0;
    put(fd, digits);
}

static uintptr_t strip(uintptr_t address) {
#if __has_feature(ptrauth_calls)
    return (uintptr_t)ptrauth_strip((void *)address, ptrauth_key_return_address);
#else
    return address;
#endif
}

static void putFrame(int fd, uintptr_t address) {
    Dl_info info;
    put(fd, "  ");
    putHex(fd, address);
    if (dladdr((void *)address, &info) && info.dli_fname) {
        const char *name = info.dli_fname, *slash = name;
        for (const char *c = name; *c; c++) if (*c == '/') slash = c + 1;
        put(fd, " ");
        put(fd, slash);
        put(fd, " +");
        putHex(fd, address - (uintptr_t)info.dli_fbase);
        if (info.dli_sname) {
            put(fd, " ");
            put(fd, info.dli_sname);
        }
    }
    put(fd, "\n");
}

static void handler(int signal, siginfo_t *info, void *context) {
    int fd = open(sg_path, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (fd >= 0) {
        put(fd, "signal ");
        putHex(fd, (uintptr_t)signal);
        put(fd, " at ");
        putHex(fd, (uintptr_t)(info ? info->si_addr : 0));
        put(fd, "\n");
        ucontext_t *uc = context;
        if (uc && uc->uc_mcontext) {
            uintptr_t pc = strip((uintptr_t)arm_thread_state64_get_pc(uc->uc_mcontext->__ss));
            uintptr_t lr = strip((uintptr_t)arm_thread_state64_get_lr(uc->uc_mcontext->__ss));
            uintptr_t fp = (uintptr_t)arm_thread_state64_get_fp(uc->uc_mcontext->__ss);
            putFrame(fd, pc);
            putFrame(fd, lr);
            // A recursion repeats one frame thousands of times: the first kMaxFrames say which.
            for (int i = 0; i < kMaxFrames && fp && !(fp & 7); i++) {
                uintptr_t *frame = (uintptr_t *)fp;
                uintptr_t next = frame[0], ret = strip(frame[1]);
                if (!ret) break;
                putFrame(fd, ret);
                if (next <= fp) break;
                fp = next;
            }
        }
        close(fd);
    }
    // The handler that was there before, or the default, which ends the process with this signal.
    for (int i = 0; i < kSignalCount; i++) {
        if (kSignals[i] != signal) continue;
        struct sigaction previous = sg_previous[i];
        if ((previous.sa_flags & SA_SIGINFO) && previous.sa_sigaction) {
            sigaction(signal, &previous, NULL);
            previous.sa_sigaction(signal, info, context);
            return;
        }
        if (previous.sa_handler != SIG_DFL && previous.sa_handler != SIG_IGN && previous.sa_handler) {
            sigaction(signal, &previous, NULL);
            previous.sa_handler(signal);
            return;
        }
    }
    struct sigaction fallback = {0};
    fallback.sa_handler = SIG_DFL;
    sigaction(signal, &fallback, NULL);
    raise(signal);
}

static void logLastCrash(NSString *path) {
    NSString *text = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
    if (!text.length) return;
    [NSFileManager.defaultManager removeItemAtPath:path error:nil];
    SGLog(@"crash trace: the last launch ended on a signal");
    for (NSString *line in [text componentsSeparatedByString:@"\n"]) {
        if (line.length) SGLog(@"crash trace: %@", line);
    }
}

static void install(void) {
    static void *altStack;
    altStack = malloc(SIGSTKSZ * 4);
    stack_t stack = {.ss_sp = altStack, .ss_size = SIGSTKSZ * 4, .ss_flags = 0};
    sigaltstack(&stack, NULL);
    for (int i = 0; i < kSignalCount; i++) {
        struct sigaction action = {0};
        action.sa_sigaction = handler;
        action.sa_flags = SA_SIGINFO | SA_ONSTACK;
        sigemptyset(&action.sa_mask);
        sigaction(kSignals[i], &action, &sg_previous[i]);
    }
}

__attribute__((constructor)) static void SGCrashTraceInit(void) {
    NSString *caches = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject;
    NSString *path = [caches stringByAppendingPathComponent:@"sg-crash.txt"];
    if (!path || path.length >= sizeof sg_path) return;
    strlcpy(sg_path, path.fileSystemRepresentation, sizeof sg_path);
    logLastCrash(path);
    // After Spotify's own launch has set its crash reporter up, so the trace goes first and hands on to it.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        install();
        SGLog(@"crash trace: watching for a crash");
    });
}

#endif
