#import "CMpv.h"
#import <OpenGL/gl3.h>
#import <dlfcn.h>

// Public libmpv ABI types (mpv/client.h, render.h, render_gl.h).
typedef struct mpv_handle mpv_handle;
typedef struct mpv_render_context mpv_render_context;
typedef struct { int type; void *data; } RenderParam;
typedef struct { void *(*get_proc_address)(void *, const char *); void *ctx; } GLInit;
typedef struct { int fbo, w, h, internal_format; } GLFBO;
typedef struct Node Node;
typedef struct { int num; Node *values; char **keys; } NodeList;
struct Node { union { char *string; int flag; int64_t int64; double number; NodeList *list; void *bytes; } u; int format; };
typedef struct { int event_id; int error; uint64_t reply_userdata; void *data; } Event;

@interface LPMpvView () {
    void *_library; mpv_handle *_mpv; mpv_render_context *_renderer;
    mpv_handle *(*create)(void); int (*initialize)(mpv_handle *);
    int (*option)(mpv_handle *, const char *, const char *);
    int (*commandAsync)(mpv_handle *, uint64_t, const char **);
    int (*property)(mpv_handle *, const char *, int, void *);
    int (*setAsync)(mpv_handle *, uint64_t, const char *, int, void *);
    void (*freeMemory)(void *); void (*freeNode)(Node *); void (*destroy)(mpv_handle *);
    Event *(*waitEvent)(mpv_handle *, double); const char *(*errorString)(int);
    int (*renderCreate)(mpv_render_context **, mpv_handle *, RenderParam *);
    void (*renderFrame)(mpv_render_context *, RenderParam *);
    void (*renderCallback)(mpv_render_context *, void (*)(void *), void *);
    void (*renderFree)(mpv_render_context *);
    NSMutableArray<NSString *> *_errors;
    dispatch_queue_t _renderQueue;
    NSOpenGLContext *_renderGL;
}
@property(nonatomic, readwrite) BOOL engineReady;
@property(nonatomic, readwrite) BOOL fileLoaded;
@property(nonatomic, readwrite) BOOL playbackFailed;
@property(nonatomic, readwrite, nullable) NSString *engineError;
@end

static void *resolveGL(void *ctx, const char *name) { return dlsym(RTLD_DEFAULT, name); }
static void updateFrame(void *ctx) {
    __weak LPMpvView *view = (__bridge LPMpvView *)ctx;
    dispatch_async(dispatch_get_main_queue(), ^{ [view setNeedsDisplay:YES]; });
}
static id foundationNode(Node n) {
    switch (n.format) {
        case 1: return n.u.string ? @(n.u.string) : @"";
        case 3: return @(n.u.flag != 0);
        case 4: return @(n.u.int64);
        case 5: return @(n.u.number);
        case 7: {
            NSMutableArray *array = [NSMutableArray array];
            for (int i = 0; i < n.u.list->num; i++) [array addObject:foundationNode(n.u.list->values[i])];
            return array;
        }
        case 8: {
            NSMutableDictionary *dict = [NSMutableDictionary dictionary];
            for (int i = 0; i < n.u.list->num; i++) dict[@(n.u.list->keys[i])] = foundationNode(n.u.list->values[i]);
            return dict;
        }
        default: return [NSNull null];
    }
}

@implementation LPMpvView
- (instancetype)initWithFrame:(NSRect)frame {
    NSOpenGLPixelFormatAttribute attributes[] = {NSOpenGLPFAOpenGLProfile, NSOpenGLProfileVersion3_2Core, NSOpenGLPFADoubleBuffer, NSOpenGLPFAAccelerated, 0};
    NSOpenGLPixelFormat *format = [[NSOpenGLPixelFormat alloc] initWithAttributes:attributes];
    self = [super initWithFrame:frame pixelFormat:format];
    if (self) {
        self.wantsBestResolutionOpenGLSurface = YES; _errors = [NSMutableArray array];
        _renderQueue = dispatch_queue_create("local.lumenplayer.render", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}
- (BOOL)startEngine:(NSString *)libraryPath {
    _library = dlopen(libraryPath.fileSystemRepresentation, RTLD_NOW | RTLD_LOCAL);
    if (!_library) { self.engineError = @(dlerror()); return NO; }
#define LOAD(field, symbol) field = dlsym(_library, symbol); if (!field) { self.engineError = @"The libmpv runtime is missing a required API."; return NO; }
    LOAD(create,"mpv_create"); LOAD(initialize,"mpv_initialize"); LOAD(option,"mpv_set_option_string");
    LOAD(commandAsync,"mpv_command_async"); LOAD(property,"mpv_get_property"); LOAD(setAsync,"mpv_set_property_async");
    LOAD(freeMemory,"mpv_free"); LOAD(freeNode,"mpv_free_node_contents"); LOAD(destroy,"mpv_terminate_destroy");
    LOAD(waitEvent,"mpv_wait_event"); LOAD(errorString,"mpv_error_string");
    LOAD(renderCreate,"mpv_render_context_create"); LOAD(renderFrame,"mpv_render_context_render");
    LOAD(renderCallback,"mpv_render_context_set_update_callback"); LOAD(renderFree,"mpv_render_context_free");
#undef LOAD
    _mpv = create();
    if (!_mpv) { self.engineError = @"Could not create the playback engine."; return NO; }
    option(_mpv,"config","no"); option(_mpv,"vo","libmpv"); option(_mpv,"hwdec","auto-safe");
    option(_mpv,"terminal","no"); option(_mpv,"keep-open","yes"); option(_mpv,"idle","yes");
    option(_mpv,"input-default-bindings","no"); option(_mpv,"osc","no"); option(_mpv,"sub-auto","fuzzy");
    option(_mpv,"audio-client-name","Lumen Player"); option(_mpv,"ytdl","no");
    int result = initialize(_mpv);
    if (result < 0) { self.engineError = @(errorString(result)); return NO; }
    _renderGL = self.openGLContext;
    if (!_renderGL) { self.engineError = @"OpenGL context unavailable."; return NO; }
    __block int renderResult;
    dispatch_sync(_renderQueue, ^{
        [self->_renderGL makeCurrentContext];
        GLInit init = {resolveGL, NULL}; char api[] = "opengl";
        RenderParam params[] = {{1, api}, {2, &init}, {0, NULL}};
        renderResult = self->renderCreate(&self->_renderer, self->_mpv, params);
        if (renderResult >= 0) self->renderCallback(self->_renderer, updateFrame, (__bridge void *)self);
        [NSOpenGLContext clearCurrentContext];
    });
    if (renderResult < 0) { self.engineError = @(errorString(renderResult)); return NO; }
    self.engineReady = YES; return YES;
}
- (void)drawRect:(NSRect)dirtyRect {
    NSRect bounds = [self convertRectToBacking:self.bounds];
    NSOpenGLContext *context = _renderGL;
    if (!context) return;
    // libmpv rendering must not share a thread with synchronous client-property reads.
    dispatch_async(_renderQueue, ^{
        CGLLockContext(context.CGLContextObj);
        [context makeCurrentContext];
        if (self->_renderer && bounds.size.width > 0 && bounds.size.height > 0) {
            GLFBO fbo = {0, (int)bounds.size.width, (int)bounds.size.height, 0}; int flip = 1;
            RenderParam params[] = {{3, &fbo}, {4, &flip}, {0, NULL}};
            self->renderFrame(self->_renderer, params);
        } else { glClearColor(0,0,0,1); glClear(GL_COLOR_BUFFER_BIT); }
        [context flushBuffer];
        [NSOpenGLContext clearCurrentContext];
        CGLUnlockContext(context.CGLContextObj);
    });
}
- (void)reshape {
    NSOpenGLContext *context = self.openGLContext;
    if (context) CGLLockContext(context.CGLContextObj);
    [super reshape];
    if (context) CGLUnlockContext(context.CGLContextObj);
    self.needsDisplay = YES;
}
- (void)command:(NSArray<NSString *> *)arguments {
    if (!_mpv) return;
    if ([arguments.firstObject isEqualToString:@"loadfile"]) { self.fileLoaded = NO; self.playbackFailed = NO; }
    const char **args = calloc(arguments.count + 1, sizeof(char *));
    for (NSUInteger i = 0; i < arguments.count; i++) args[i] = arguments[i].UTF8String;
    int result = commandAsync(_mpv, 0, args); free(args);
    if (result < 0) [_errors addObject:@(errorString(result))];
}
- (void)setProperty:(NSString *)name value:(NSString *)value {
    if (!_mpv) return; const char *text = value.UTF8String;
    int result = setAsync(_mpv, 0, name.UTF8String, 1, &text);
    if (result < 0) [_errors addObject:@(errorString(result))];
}
- (NSString *)stringProperty:(NSString *)name {
    if (!_mpv) return nil; char *value = NULL;
    if (property(_mpv, name.UTF8String, 1, &value) < 0 || !value) return nil;
    NSString *s = @(value); freeMemory(value); return s;
}
- (double)numberProperty:(NSString *)name {
    double value = 0; if (_mpv) property(_mpv, name.UTF8String, 5, &value); return value;
}
- (BOOL)flagProperty:(NSString *)name {
    int value = 0; if (_mpv) property(_mpv, name.UTF8String, 3, &value); return value != 0;
}
- (NSArray *)nodeArray:(NSString *)name {
    if (!_mpv) return @[]; Node node = {0};
    if (property(_mpv, name.UTF8String, 6, &node) < 0) return @[];
    id value = foundationNode(node); freeNode(&node);
    return [value isKindOfClass:NSArray.class] ? value : @[];
}
- (NSArray *)tracks { return [self nodeArray:@"track-list"]; }
- (NSArray *)chapters { return [self nodeArray:@"chapter-list"]; }
- (NSArray<NSString *> *)drainErrors {
    if (_mpv) {
        Event *event;
        while ((event = waitEvent(_mpv, 0))->event_id != 0) {
            if (event->event_id == 6) self.fileLoaded = NO;
            if (event->event_id == 8) self.fileLoaded = YES;
            if (event->error < 0) [_errors addObject:@(errorString(event->error))];
            // MPV_EVENT_END_FILE; the first fields are reason and error.
            if (event->event_id == 7 && event->data) {
                int *end = event->data;
                if (end[0] == 4 && end[1] < 0) { self.playbackFailed = YES; [_errors addObject:@(errorString(end[1]))]; }
            }
        }
    }
    NSArray *errors = [_errors copy]; [_errors removeAllObjects]; return errors;
}
- (void)shutdown {
    self.engineReady = NO;
    if (_renderer) {
        dispatch_sync(_renderQueue, ^{
            self->renderCallback(self->_renderer,NULL,NULL);
            [self->_renderGL makeCurrentContext]; self->renderFree(self->_renderer); self->_renderer = NULL;
            [NSOpenGLContext clearCurrentContext];
        });
    }
    if (_mpv) { destroy(_mpv); _mpv = NULL; }
    // Keep the dynamic image loaded until process exit (libmpv owns worker TLS).
}
- (void)dealloc { [self shutdown]; }
@end
