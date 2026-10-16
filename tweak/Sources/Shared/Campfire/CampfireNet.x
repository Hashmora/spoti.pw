// A log of the requests Spotify's own network layer gets an error or a 4xx/5xx for, once each as host, path
// and status (no query, no headers, no body), through the same three URLSession delegates Shared/AdBlock reads
// responses by. For finding which request makes a screen say it could not load: open it, then
// make log | grep "campfire net". It changes nothing.
#import "Core/SGCore.h"

static void note(NSURLSessionTask *task, NSError *error) {
    NSURL *url = task.currentRequest.URL ?: task.originalRequest.URL;
    if (!url) return;
    if ([error.domain isEqualToString:NSURLErrorDomain] && error.code == NSURLErrorCancelled) return;
    NSInteger status = [task.response isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse *)task.response).statusCode : 0;
    if (status < 400 && !error) return;
    static NSMutableSet<NSString *> *seen;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ seen = [NSMutableSet set]; });
    NSString *line = [NSString stringWithFormat:@"%ld %@%@%@", (long)status, url.host ?: @"", url.path ?: @"",
                      error ? [NSString stringWithFormat:@" (error %ld)", (long)error.code] : @""];
    @synchronized (seen) {
        if ([seen containsObject:line]) return;
        [seen addObject:line];
    }
    SGLog(@"campfire net: %@", line);
}

%hook SPTDataLoaderService
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    %orig;
    note(task, error);
}
%end

%hook _TtC26Connectivity_HttpClientKit20HttpClientURLSession
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    %orig;
    note(task, error);
}
%end

%hook SPTCoreURLSessionDataDelegate
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    %orig;
    note(task, error);
}
%end

%ctor {
    %init;
}
