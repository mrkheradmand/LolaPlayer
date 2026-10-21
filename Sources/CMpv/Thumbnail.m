#import "CMpv.h"
#import <dlfcn.h>
#import <math.h>

typedef struct { void *data; size_t size; } ThumbBytes;
typedef struct ThumbNode ThumbNode;
typedef struct { int num; ThumbNode *values; char **keys; } ThumbList;
struct ThumbNode { union { char *string; int flag; int64_t integer; double number; ThumbList *list; ThumbBytes *bytes; } u; int format; };
typedef struct { int event_id; int error; uint64_t reply; void *data; } ThumbEvent;

@implementation LPThumbnailDecoder {
    void *_library, *_mpv;
    NSString *_path;
    BOOL _hasFrame;
    void *(*create)(void);
    int (*option)(void *, const char *, const char *);
    int (*initialize)(void *);
    int (*command)(void *, const char **);
    int (*commandRet)(void *, const char **, ThumbNode *);
    int (*property)(void *, const char *, int, void *);
    ThumbEvent *(*waitEvent)(void *, double);
    void (*freeNode)(ThumbNode *);
    void (*destroy)(void *);
}
// Used exclusively by the Swift decoder actor, never by the UI/render thread.
- (NSDictionary *)frameAtPath:(NSString *)path seconds:(double)seconds library:(NSString *)library exact:(BOOL)exact {
    if (!isfinite(seconds) || seconds < 0) return nil;
    if (!_mpv) {
        _library = dlopen(library.fileSystemRepresentation, RTLD_NOW | RTLD_LOCAL);
        if (!_library) return nil;
#define THUMB_LOAD(field, symbol) field = dlsym(_library, symbol); if (!field) return nil;
        THUMB_LOAD(create, "mpv_create"); THUMB_LOAD(option, "mpv_set_option_string");
        THUMB_LOAD(initialize, "mpv_initialize"); THUMB_LOAD(command, "mpv_command");
        THUMB_LOAD(commandRet, "mpv_command_ret"); THUMB_LOAD(property, "mpv_get_property");
        THUMB_LOAD(waitEvent, "mpv_wait_event"); THUMB_LOAD(freeNode, "mpv_free_node_contents");
        THUMB_LOAD(destroy, "mpv_terminate_destroy");
#undef THUMB_LOAD
        _mpv = create();
        if (!_mpv) return nil;
        option(_mpv, "config", "no"); option(_mpv, "terminal", "no");
        option(_mpv, "vo", "null"); option(_mpv, "aid", "no"); option(_mpv, "sid", "no");
        option(_mpv, "audio-display", "no"); option(_mpv, "pause", "yes");
        option(_mpv, "keep-open", "yes"); option(_mpv, "idle", "yes");
        option(_mpv, "hwdec", "no"); option(_mpv, "vd-lavc-threads", "2");
        option(_mpv, "ytdl", "no"); option(_mpv, "load-scripts", "no");
        option(_mpv, "vf", "lavfi=[scale=320:180:force_original_aspect_ratio=decrease]");
        if (initialize(_mpv) < 0) { destroy(_mpv); _mpv = NULL; return nil; }
    }
    while (waitEvent(_mpv, 0)->event_id != 0) {}
    double position = -1;
    if (_hasFrame) property(_mpv, "time-pos", 5, &position);
    BOOL alreadyAtFrame = _hasFrame && [_path isEqualToString:path] && fabs(position - seconds) < 0.02;
    if (!alreadyAtFrame) {
        int status;
        if (_hasFrame && [_path isEqualToString:path]) {
            NSString *target = [NSString stringWithFormat:@"%.3f", seconds];
            const char *seek[] = {"seek", target.UTF8String, exact ? "absolute+exact" : "absolute+keyframes", NULL};
            status = command(_mpv, seek);
        } else {
            NSString *start = [NSString stringWithFormat:@"start=%.3f", seconds];
            const char *load[] = {"loadfile", path.fileSystemRepresentation, "replace", "-1", start.UTF8String, NULL};
            status = command(_mpv, load);
        }
        if (status < 0) return nil;
    }
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:3];
    BOOL ready = alreadyAtFrame;
    while (!ready && [deadline timeIntervalSinceNow] > 0) {
        ThumbEvent *event = waitEvent(_mpv, 0.05);
        if (event->event_id == 21) { ready = YES; break; } // MPV_EVENT_PLAYBACK_RESTART
        if (event->event_id == 7 && event->data && ((int *)event->data)[0] == 4) break;
    }
    NSDictionary *result = nil;
    if (ready) {
        ThumbNode node = {0};
        const char *raw[] = {"screenshot-raw", "video", "rgba", NULL};
        if (commandRet(_mpv, raw, &node) >= 0 && node.format == 8) {
            int64_t width = 0, height = 0, stride = 0;
            ThumbBytes *bytes = NULL;
            for (int i = 0; i < node.u.list->num; i++) {
                const char *key = node.u.list->keys[i]; ThumbNode n = node.u.list->values[i];
                if (!strcmp(key, "w") && n.format == 4) width = n.u.integer;
                if (!strcmp(key, "h") && n.format == 4) height = n.u.integer;
                if (!strcmp(key, "stride") && n.format == 4) stride = n.u.integer;
                if (!strcmp(key, "data") && n.format == 9) bytes = n.u.bytes;
            }
            if (width > 0 && width <= 640 && height > 0 && height <= 640 && stride >= width * 4
                && stride <= 4096 && bytes && bytes->data && bytes->size >= stride * height) {
                double actual = seconds; property(_mpv, "time-pos", 5, &actual);
                if (!isfinite(actual)) actual = seconds;
                result = @{ @"pixels": [NSData dataWithBytes:bytes->data length:stride * height],
                    @"width": @(width), @"height": @(height), @"stride": @(stride), @"time": @(actual) };
            }
        }
        freeNode(&node);
    }
    if (result) { _path = [path copy]; _hasFrame = YES; }
    else { _path = nil; _hasFrame = NO; const char *stop[] = {"stop", NULL}; command(_mpv, stop); }
    return result;
}
- (void)reset {
    _path = nil; _hasFrame = NO;
    if (_mpv) { const char *stop[] = {"stop", NULL}; command(_mpv, stop); }
}
- (void)dealloc {
    if (_mpv) destroy(_mpv);
    // libmpv owns worker TLS; keep its dynamic image loaded until process exit.
}
@end
