// cwindow for Android: one window, the NativeActivity's.
//
// The platform launches the app by loading its library and calling
// ANativeActivity_onCreate on the UI thread. That is where this starts: it
// takes the activity's callbacks and runs the program's own main on a thread
// of its own, since the UI thread must keep returning to its looper. The
// callbacks, on the UI thread, queue events; the program, on its thread,
// takes them with cwindow_next and draws with cwindow_present.
//
// No NDK is needed to build this: the few NDK declarations it uses are
// written out below, from the platform's stable C ABI. Their layouts are
// the NDK's, and must stay so.
//
// The window is the activity's, so there is one; cwindow_create waits for
// the platform to hand it over and answers 1. A frame is a timer at the
// display's usual 60 Hz, and the program's standard output and error go to
// logcat under the tag "vertex".

#include <stdint.h>
#include <stddef.h>

#include "cwindow.h"

// ---- The platform, declared -------------------------------------------------

typedef struct ANativeWindow ANativeWindow;
typedef struct AInputQueue AInputQueue;
typedef struct AInputEvent AInputEvent;
typedef struct AAssetManager AAssetManager;
typedef struct AConfiguration AConfiguration;
typedef struct ALooper ALooper;
typedef struct ARect {
    int32_t left, top, right, bottom;
} ARect;

struct ANativeActivity;

typedef struct ANativeActivityCallbacks {
    void (*onStart)(struct ANativeActivity*);
    void (*onResume)(struct ANativeActivity*);
    void* (*onSaveInstanceState)(struct ANativeActivity*, size_t*);
    void (*onPause)(struct ANativeActivity*);
    void (*onStop)(struct ANativeActivity*);
    void (*onDestroy)(struct ANativeActivity*);
    void (*onWindowFocusChanged)(struct ANativeActivity*, int);
    void (*onNativeWindowCreated)(struct ANativeActivity*, ANativeWindow*);
    void (*onNativeWindowResized)(struct ANativeActivity*, ANativeWindow*);
    void (*onNativeWindowRedrawNeeded)(struct ANativeActivity*, ANativeWindow*);
    void (*onNativeWindowDestroyed)(struct ANativeActivity*, ANativeWindow*);
    void (*onInputQueueCreated)(struct ANativeActivity*, AInputQueue*);
    void (*onInputQueueDestroyed)(struct ANativeActivity*, AInputQueue*);
    void (*onContentRectChanged)(struct ANativeActivity*, const ARect*);
    void (*onConfigurationChanged)(struct ANativeActivity*);
    void (*onLowMemory)(struct ANativeActivity*);
} ANativeActivityCallbacks;

typedef struct ANativeActivity {
    ANativeActivityCallbacks* callbacks;
    void* vm;
    void* env;
    void* clazz;
    const char* internalDataPath;
    const char* externalDataPath;
    int32_t sdkVersion;
    void* instance;
    AAssetManager* assetManager;
    const char* obbPath;
} ANativeActivity;

typedef struct ANativeWindow_Buffer {
    int32_t width;
    int32_t height;
    int32_t stride;
    int32_t format;
    void* bits;
    uint32_t reserved[6];
} ANativeWindow_Buffer;

enum { WINDOW_FORMAT_RGBA_8888 = 1 };

void ANativeActivity_finish(ANativeActivity* activity);
void ANativeWindow_acquire(ANativeWindow* window);
void ANativeWindow_release(ANativeWindow* window);
int32_t ANativeWindow_getWidth(ANativeWindow* window);
int32_t ANativeWindow_getHeight(ANativeWindow* window);
int32_t ANativeWindow_setBuffersGeometry(ANativeWindow* window, int32_t width, int32_t height, int32_t format);
int32_t ANativeWindow_lock(ANativeWindow* window, ANativeWindow_Buffer* out, ARect* dirty);
int32_t ANativeWindow_unlockAndPost(ANativeWindow* window);

typedef int (*ALooper_callbackFunc)(int fd, int events, void* data);
ALooper* ALooper_forThread(void);
int32_t AInputQueue_getEvent(AInputQueue* queue, AInputEvent** out);
int32_t AInputQueue_preDispatchEvent(AInputQueue* queue, AInputEvent* event);
void AInputQueue_finishEvent(AInputQueue* queue, AInputEvent* event, int handled);
void AInputQueue_attachLooper(AInputQueue* queue, ALooper* looper, int ident, ALooper_callbackFunc callback,
                              void* data);
void AInputQueue_detachLooper(AInputQueue* queue);
int32_t AInputEvent_getType(const AInputEvent* event);
int32_t AMotionEvent_getAction(const AInputEvent* event);
float AMotionEvent_getX(const AInputEvent* event, size_t pointer);
float AMotionEvent_getY(const AInputEvent* event, size_t pointer);
float AMotionEvent_getPressure(const AInputEvent* event, size_t pointer);
int32_t AKeyEvent_getAction(const AInputEvent* event);
int32_t AKeyEvent_getKeyCode(const AInputEvent* event);

AConfiguration* AConfiguration_new(void);
void AConfiguration_delete(AConfiguration* config);
void AConfiguration_fromAssetManager(AConfiguration* config, AAssetManager* assets);
int32_t AConfiguration_getDensity(AConfiguration* config);
int32_t AConfiguration_getUiModeNight(AConfiguration* config);

int __android_log_write(int priority, const char* tag, const char* text);

// Bionic.
typedef struct {
    int32_t private_[10];
} pthread_mutex_t;
typedef struct {
    int32_t private_[12];
} pthread_cond_t;
typedef long pthread_t;
int pthread_create(pthread_t* thread, const void* attr, void* (*start)(void*), void* arg);
int pthread_detach(pthread_t thread);
int pthread_mutex_lock(pthread_mutex_t* mutex);
int pthread_mutex_unlock(pthread_mutex_t* mutex);
int pthread_cond_wait(pthread_cond_t* cond, pthread_mutex_t* mutex);
int pthread_cond_broadcast(pthread_cond_t* cond);

struct timespec {
    long tv_sec;
    long tv_nsec;
};
struct itimerspec {
    struct timespec it_interval;
    struct timespec it_value;
};
struct epoll_event {
    uint32_t events;
    uint64_t data;
};
int clock_gettime(int clock, struct timespec* ts);
int timerfd_create(int clock, int flags);
int timerfd_settime(int fd, int flags, const struct itimerspec* value, struct itimerspec* old);
int eventfd(unsigned int initval, int flags);
int epoll_create1(int flags);
int epoll_ctl(int epfd, int op, int fd, struct epoll_event* event);
long read(int fd, void* buf, size_t count);
long write(int fd, const void* buf, size_t count);
int pipe(int fds[2]);
int dup2(int from, int to);
void* memcpy(void* dest, const void* src, size_t count);
void* memset(void* dest, int byte, size_t count);
void exit(int status);

enum {
    CLOCK_MONOTONIC = 1,
    O_NONBLOCK = 04000,
    O_CLOEXEC = 02000000,
    EPOLLIN = 1,
    EPOLL_CTL_ADD = 1,
    ANDROID_LOG_INFO = 4
};

// The Vertex program: vsc names its entry main.
int main(int argc, char** argv);

// ---- State ------------------------------------------------------------------

#define QUEUE_CAP 256
#define TEXT_CAP 16

typedef struct Event {
    int32_t kind, code, modifiers, flags;
    double x, y, pressure, time, interval;
    char text[TEXT_CAP];
} Event;

// Everything below is guarded by lock, which both threads take.
static pthread_mutex_t lock;
static pthread_cond_t changed;

static ANativeActivity* activity;
static ANativeWindow* nativeWindow;
static AInputQueue* inputQueue;
static int running;    // the program's thread has been started
static int created;    // cwindow_create has answered
static int closed;     // cwindow_close, or the activity is gone
static int focused;
static int theme;
static double scale = 1;
static int32_t bufWidth, bufHeight;  // the geometry last set on the window

static Event items[QUEUE_CAP];
static int head, count;
static Event cur;

// The window's descriptor is an epoll set of two: queued, readable while the
// queue is not empty, and timer, readable once a requested frame is due.
static int descriptor = -1;
static int queued = -1;
static int timer = -1;

static double now(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec + (double)ts.tv_nsec / 1e9;
}

// push queues an event; the lock is held.
static void push(Event e) {
    if (count == QUEUE_CAP || created == 0)
        return;
    items[(head + count) % QUEUE_CAP] = e;
    count++;
    if (count == 1 && queued >= 0) {
        uint64_t one = 1;
        write(queued, &one, sizeof one);
    }
}

static Event make(int32_t kind) {
    Event e;
    memset(&e, 0, sizeof e);
    e.kind = kind;
    e.time = now();
    return e;
}

static void pushKind(int32_t kind) { push(make(kind)); }

static void pushSize(void) {
    if (nativeWindow == NULL)
        return;
    Event e = make(CWINDOW_EVENT_RESIZED);
    e.x = ANativeWindow_getWidth(nativeWindow) / scale;
    e.y = ANativeWindow_getHeight(nativeWindow) / scale;
    push(e);
}

// readConfiguration takes the display's density and night mode.
static void readConfiguration(ANativeActivity* a) {
    AConfiguration* config = AConfiguration_new();
    if (config == NULL)
        return;
    AConfiguration_fromAssetManager(config, a->assetManager);
    int32_t density = AConfiguration_getDensity(config);
    scale = density > 0 ? density / 160.0 : 1;
    theme = AConfiguration_getUiModeNight(config) == 2 ? 1 : 0;
    AConfiguration_delete(config);
}

// ---- Standard output to logcat ----------------------------------------------

static void* logMain(void* arg) {
    int fd = (int)(long)arg;
    char line[1024];
    int n = 0;
    for (;;) {
        char c;
        long got = read(fd, &c, 1);
        if (got <= 0)
            return NULL;
        if (c == '\n' || n == (int)sizeof line - 1) {
            line[n] = 0;
            __android_log_write(ANDROID_LOG_INFO, "vertex", line);
            n = 0;
            if (c == '\n')
                continue;
        }
        line[n++] = c;
    }
}

static void redirectOutput(void) {
    int fds[2];
    if (pipe(fds) != 0)
        return;
    dup2(fds[1], 1);
    dup2(fds[1], 2);
    pthread_t t;
    if (pthread_create(&t, NULL, logMain, (void*)(long)fds[0]) == 0)
        pthread_detach(t);
}

// ---- The program's thread ---------------------------------------------------

static void* programMain(void* arg) {
    (void)arg;
    static char name[] = "vertex";
    char* argv[2];
    argv[0] = name;
    argv[1] = NULL;
    int status = main(1, argv);
    pthread_mutex_lock(&lock);
    closed = 1;
    ANativeActivity* a = activity;
    pthread_mutex_unlock(&lock);
    if (a != NULL)
        ANativeActivity_finish(a);
    // The program is over, and so is the process, as it would be on a
    // desktop: Android would otherwise keep it cached, and the next launch
    // would find main already run.
    exit(status);
    return NULL;
}

// ---- Activity callbacks, on the UI thread -----------------------------------

static void onDestroy(ANativeActivity* a) {
    (void)a;
    pthread_mutex_lock(&lock);
    activity = NULL;
    pushKind(CWINDOW_EVENT_CLOSE_REQUESTED);
    pthread_cond_broadcast(&changed);
    pthread_mutex_unlock(&lock);
}

static void onWindowFocusChanged(ANativeActivity* a, int hasFocus) {
    (void)a;
    pthread_mutex_lock(&lock);
    focused = hasFocus != 0;
    Event e = make(CWINDOW_EVENT_FOCUS_CHANGED);
    e.code = focused;
    push(e);
    pthread_mutex_unlock(&lock);
}

static void onNativeWindowCreated(ANativeActivity* a, ANativeWindow* window) {
    (void)a;
    pthread_mutex_lock(&lock);
    ANativeWindow_acquire(window);
    nativeWindow = window;
    bufWidth = bufHeight = 0;
    pushSize();
    pushKind(CWINDOW_EVENT_FRAME);
    pthread_cond_broadcast(&changed);
    pthread_mutex_unlock(&lock);
}

static void onNativeWindowResized(ANativeActivity* a, ANativeWindow* window) {
    (void)a;
    (void)window;
    pthread_mutex_lock(&lock);
    pushSize();
    pthread_mutex_unlock(&lock);
}

static void onNativeWindowRedrawNeeded(ANativeActivity* a, ANativeWindow* window) {
    (void)a;
    (void)window;
    pthread_mutex_lock(&lock);
    pushKind(CWINDOW_EVENT_FRAME);
    pthread_mutex_unlock(&lock);
}

// Taking the lock waits out a present in progress: the window is not the
// program's to draw into once this returns.
static void onNativeWindowDestroyed(ANativeActivity* a, ANativeWindow* window) {
    (void)a;
    pthread_mutex_lock(&lock);
    if (nativeWindow == window) {
        ANativeWindow_release(nativeWindow);
        nativeWindow = NULL;
    }
    pthread_mutex_unlock(&lock);
}

static void onConfigurationChanged(ANativeActivity* a) {
    pthread_mutex_lock(&lock);
    double oldScale = scale;
    int oldTheme = theme;
    readConfiguration(a);
    if (scale != oldScale) {
        Event e = make(CWINDOW_EVENT_SCALE_CHANGED);
        e.x = scale;
        push(e);
        pushSize();
    }
    if (theme != oldTheme) {
        Event e = make(CWINDOW_EVENT_THEME_CHANGED);
        e.code = theme;
        push(e);
    }
    pthread_mutex_unlock(&lock);
}

// A touch is the primary button of a pointer; Back asks to close.
static int handleInput(AInputEvent* ev) {
    int32_t type = AInputEvent_getType(ev);
    if (type == 2) {  // AINPUT_EVENT_TYPE_MOTION
        int32_t action = AMotionEvent_getAction(ev) & 0xff;
        int32_t kind;
        switch (action) {
        case 0:  // AMOTION_EVENT_ACTION_DOWN
        case 5:  // AMOTION_EVENT_ACTION_POINTER_DOWN
            kind = CWINDOW_EVENT_POINTER_DOWN;
            break;
        case 1:  // AMOTION_EVENT_ACTION_UP
        case 6:  // AMOTION_EVENT_ACTION_POINTER_UP
            kind = CWINDOW_EVENT_POINTER_UP;
            break;
        case 2:  // AMOTION_EVENT_ACTION_MOVE
            kind = CWINDOW_EVENT_POINTER_MOVED;
            break;
        case 3:  // AMOTION_EVENT_ACTION_CANCEL
            kind = CWINDOW_EVENT_POINTER_LEFT;
            break;
        default:
            return 0;
        }
        Event e = make(kind);
        e.x = AMotionEvent_getX(ev, 0) / scale;
        e.y = AMotionEvent_getY(ev, 0) / scale;
        e.pressure = AMotionEvent_getPressure(ev, 0);
        if (kind == CWINDOW_EVENT_POINTER_DOWN || kind == CWINDOW_EVENT_POINTER_UP)
            e.flags = 1 << 8;
        push(e);
        return 1;
    }
    if (type == 1) {  // AINPUT_EVENT_TYPE_KEY
        if (AKeyEvent_getKeyCode(ev) == 4) {  // AKEYCODE_BACK
            if (AKeyEvent_getAction(ev) == 1)  // up
                pushKind(CWINDOW_EVENT_CLOSE_REQUESTED);
            return 1;
        }
    }
    return 0;
}

static int onInput(int fd, int events, void* data) {
    (void)fd;
    (void)events;
    AInputQueue* queue = (AInputQueue*)data;
    AInputEvent* ev = NULL;
    while (AInputQueue_getEvent(queue, &ev) >= 0) {
        if (AInputQueue_preDispatchEvent(queue, ev))
            continue;
        pthread_mutex_lock(&lock);
        int handled = handleInput(ev);
        pthread_mutex_unlock(&lock);
        AInputQueue_finishEvent(queue, ev, handled);
    }
    return 1;
}

static void onInputQueueCreated(ANativeActivity* a, AInputQueue* queue) {
    (void)a;
    inputQueue = queue;
    AInputQueue_attachLooper(queue, ALooper_forThread(), 1, onInput, queue);
}

static void onInputQueueDestroyed(ANativeActivity* a, AInputQueue* queue) {
    (void)a;
    AInputQueue_detachLooper(queue);
    if (inputQueue == queue)
        inputQueue = NULL;
}

void ANativeActivity_onCreate(ANativeActivity* a, void* savedState, size_t savedStateSize) {
    (void)savedState;
    (void)savedStateSize;
    ANativeActivityCallbacks* cb = a->callbacks;
    cb->onDestroy = onDestroy;
    cb->onWindowFocusChanged = onWindowFocusChanged;
    cb->onNativeWindowCreated = onNativeWindowCreated;
    cb->onNativeWindowResized = onNativeWindowResized;
    cb->onNativeWindowRedrawNeeded = onNativeWindowRedrawNeeded;
    cb->onNativeWindowDestroyed = onNativeWindowDestroyed;
    cb->onInputQueueCreated = onInputQueueCreated;
    cb->onInputQueueDestroyed = onInputQueueDestroyed;
    cb->onConfigurationChanged = onConfigurationChanged;

    pthread_mutex_lock(&lock);
    activity = a;
    readConfiguration(a);
    // An activity recreated in the same process finds the program still
    // running, and gives it the new window when it comes.
    int start = !running;
    running = 1;
    pthread_mutex_unlock(&lock);
    if (!start)
        return;
    redirectOutput();
    pthread_t t;
    if (pthread_create(&t, NULL, programMain, NULL) == 0)
        pthread_detach(t);
}

// ---- The C ABI, on the program's thread -------------------------------------

int32_t cwindow_create(const char* title, double width, double height, int32_t flags) {
    (void)title;
    (void)width;
    (void)height;
    (void)flags;
    pthread_mutex_lock(&lock);
    if (!running) {
        // A program not started by an activity -- run from a shell -- has
        // no window to be given.
        pthread_mutex_unlock(&lock);
        return CWINDOW_ERR_NO_DISPLAY;
    }
    if (created) {
        pthread_mutex_unlock(&lock);
        return CWINDOW_ERR_UNSUPPORTED;
    }
    if (descriptor < 0) {
        descriptor = epoll_create1(O_CLOEXEC);
        queued = eventfd(0, O_NONBLOCK | O_CLOEXEC);
        timer = timerfd_create(CLOCK_MONOTONIC, O_NONBLOCK | O_CLOEXEC);
        if (descriptor < 0 || queued < 0 || timer < 0) {
            pthread_mutex_unlock(&lock);
            return CWINDOW_ERR_SYSTEM;
        }
        struct epoll_event e;
        e.events = EPOLLIN;
        e.data = 0;
        epoll_ctl(descriptor, EPOLL_CTL_ADD, queued, &e);
        e.data = 1;
        epoll_ctl(descriptor, EPOLL_CTL_ADD, timer, &e);
    }
    while (nativeWindow == NULL && activity != NULL)
        pthread_cond_wait(&changed, &lock);
    if (nativeWindow == NULL) {
        pthread_mutex_unlock(&lock);
        return CWINDOW_ERR_NO_DISPLAY;
    }
    created = 1;
    closed = 0;
    // What the window has been through before the program asked for it.
    pushSize();
    pushKind(CWINDOW_EVENT_FRAME);
    if (focused) {
        Event e = make(CWINDOW_EVENT_FOCUS_CHANGED);
        e.code = 1;
        push(e);
    }
    pthread_mutex_unlock(&lock);
    return 1;
}

void cwindow_close(int32_t window) {
    if (window != 1)
        return;
    pthread_mutex_lock(&lock);
    closed = 1;
    count = 0;
    pthread_mutex_unlock(&lock);
}

int32_t cwindow_descriptor(int32_t window) {
    if (window != 1 || closed)
        return CWINDOW_ERR_INVALID;
    return descriptor;
}

int32_t cwindow_next(int32_t window) {
    if (window != 1)
        return CWINDOW_ERR_INVALID;
    pthread_mutex_lock(&lock);
    if (closed) {
        pthread_mutex_unlock(&lock);
        return CWINDOW_ERR_INVALID;
    }
    uint64_t expired = 0;
    if (read(timer, &expired, sizeof expired) > 0) {
        Event e = make(CWINDOW_EVENT_FRAME);
        e.interval = 1.0 / 60;
        push(e);
    }
    if (count == 0) {
        memset(&cur, 0, sizeof cur);
        pthread_mutex_unlock(&lock);
        return CWINDOW_EVENT_NONE;
    }
    cur = items[head];
    head = (head + 1) % QUEUE_CAP;
    count--;
    if (count == 0) {
        uint64_t drained;
        read(queued, &drained, sizeof drained);
    }
    pthread_mutex_unlock(&lock);
    return cur.kind;
}

int32_t cwindow_event_code(int32_t window) { (void)window; return cur.code; }
int32_t cwindow_event_modifiers(int32_t window) { (void)window; return cur.modifiers; }
int32_t cwindow_event_flags(int32_t window) { (void)window; return cur.flags; }
double cwindow_event_x(int32_t window) { (void)window; return cur.x; }
double cwindow_event_y(int32_t window) { (void)window; return cur.y; }
double cwindow_event_pressure(int32_t window) { (void)window; return cur.pressure; }
double cwindow_event_time(int32_t window) { (void)window; return cur.time; }
double cwindow_event_interval(int32_t window) { (void)window; return cur.interval; }

int32_t cwindow_event_text(int32_t window, char* buf, int32_t cap) {
    (void)window;
    int32_t n = 0;
    while (n < TEXT_CAP && cur.text[n] != 0)
        n++;
    if (buf != NULL && cap > 0) {
        int32_t m = n < cap - 1 ? n : cap - 1;
        for (int32_t i = 0; i < m; i++)
            buf[i] = cur.text[i];
        buf[m] = 0;
    }
    return n;
}

int32_t cwindow_pixel_width(int32_t window) {
    (void)window;
    pthread_mutex_lock(&lock);
    int32_t w = nativeWindow != NULL ? ANativeWindow_getWidth(nativeWindow) : 0;
    pthread_mutex_unlock(&lock);
    return w;
}

int32_t cwindow_pixel_height(int32_t window) {
    (void)window;
    pthread_mutex_lock(&lock);
    int32_t h = nativeWindow != NULL ? ANativeWindow_getHeight(nativeWindow) : 0;
    pthread_mutex_unlock(&lock);
    return h;
}

double cwindow_width(int32_t window) { return cwindow_pixel_width(window) / scale; }
double cwindow_height(int32_t window) { return cwindow_pixel_height(window) / scale; }
double cwindow_scale(int32_t window) { (void)window; return scale; }
int32_t cwindow_theme(int32_t window) { (void)window; return theme; }
int32_t cwindow_focused(int32_t window) { (void)window; return focused; }

// An activity's window is the screen's: its title, size and visibility are
// the platform's to decide.
void cwindow_set_title(int32_t window, const char* title) { (void)window; (void)title; }
void cwindow_set_size(int32_t window, double width, double height) { (void)window; (void)width; (void)height; }
void cwindow_set_min_size(int32_t window, double width, double height) { (void)window; (void)width; (void)height; }
void cwindow_set_visible(int32_t window, int32_t visible) { (void)window; (void)visible; }
void cwindow_set_fullscreen(int32_t window, int32_t fullscreen) { (void)window; (void)fullscreen; }
void cwindow_set_cursor(int32_t window, int32_t cursor) { (void)window; (void)cursor; }

int32_t cwindow_set_cursor_image(int32_t window, const uint8_t* rgba, int32_t width, int32_t height,
                                 int32_t hotX, int32_t hotY, double s) {
    (void)window; (void)rgba; (void)width; (void)height; (void)hotX; (void)hotY; (void)s;
    return CWINDOW_OK;
}

// One frame, a sixtieth of a second from now.
void cwindow_request_frame(int32_t window) {
    if (window != 1 || timer < 0)
        return;
    struct itimerspec t;
    memset(&t, 0, sizeof t);
    t.it_value.tv_nsec = 16666667;
    timerfd_settime(timer, 0, &t, NULL);
}

int32_t cwindow_present(int32_t window, const uint8_t* rgba, int32_t width, int32_t height) {
    if (window != 1 || rgba == NULL || width <= 0 || height <= 0)
        return CWINDOW_ERR_INVALID;
    pthread_mutex_lock(&lock);
    if (nativeWindow == NULL) {
        // Not on screen: there is nothing to show the pixels in, and the
        // window's next creation asks for a frame.
        pthread_mutex_unlock(&lock);
        return CWINDOW_OK;
    }
    if (width != bufWidth || height != bufHeight) {
        ANativeWindow_setBuffersGeometry(nativeWindow, width, height, WINDOW_FORMAT_RGBA_8888);
        bufWidth = width;
        bufHeight = height;
    }
    ANativeWindow_Buffer buf;
    if (ANativeWindow_lock(nativeWindow, &buf, NULL) != 0) {
        pthread_mutex_unlock(&lock);
        return CWINDOW_ERR_SYSTEM;
    }
    int32_t w = width < buf.width ? width : buf.width;
    int32_t h = height < buf.height ? height : buf.height;
    uint8_t* dst = (uint8_t*)buf.bits;
    for (int32_t y = 0; y < h; y++)
        memcpy(&dst[(size_t)y * (size_t)buf.stride * 4], &rgba[(size_t)y * (size_t)width * 4], (size_t)w * 4);
    ANativeWindow_unlockAndPost(nativeWindow);
    pthread_mutex_unlock(&lock);
    return CWINDOW_OK;
}

// No platform text here yet: ui/font draws text where it is wanted.
void cwindow_measure_text(const char* text, double font_size, int32_t bold, int32_t italic, double* out_w,
                          double* out_h) {
    (void)text; (void)bold; (void)italic;
    if (out_w != NULL)
        *out_w = 0;
    if (out_h != NULL)
        *out_h = font_size;
}

void cwindow_draw_text(uint8_t* rgba, int32_t buf_w, int32_t buf_h, int32_t x, int32_t y, const char* text,
                       double font_size, int32_t bold, int32_t italic, uint8_t r, uint8_t g, uint8_t b, uint8_t a,
                       double s, int32_t clip_x, int32_t clip_y, int32_t clip_w, int32_t clip_h) {
    (void)rgba; (void)buf_w; (void)buf_h; (void)x; (void)y; (void)text; (void)font_size; (void)bold;
    (void)italic; (void)r; (void)g; (void)b; (void)a; (void)s; (void)clip_x; (void)clip_y; (void)clip_w;
    (void)clip_h;
}

void cwindow_fill_rect(uint8_t* rgba, int32_t buf_w, int32_t buf_h, int32_t x, int32_t y, int32_t w, int32_t h,
                       uint8_t r, uint8_t g, uint8_t b, uint8_t a, int32_t clip_x, int32_t clip_y, int32_t clip_w,
                       int32_t clip_h) {
    int32_t x0 = x > clip_x ? x : clip_x;
    int32_t y0 = y > clip_y ? y : clip_y;
    int32_t x1 = x + w < clip_x + clip_w ? x + w : clip_x + clip_w;
    int32_t y1 = y + h < clip_y + clip_h ? y + h : clip_y + clip_h;
    if (x0 < 0) x0 = 0;
    if (y0 < 0) y0 = 0;
    if (x1 > buf_w) x1 = buf_w;
    if (y1 > buf_h) y1 = buf_h;
    uint32_t ia = 255u - a;
    for (int32_t py = y0; py < y1; py++) {
        for (int32_t px = x0; px < x1; px++) {
            size_t i = ((size_t)py * (size_t)buf_w + (size_t)px) * 4;
            rgba[i] = (uint8_t)(r + (rgba[i] * ia + 127) / 255);
            rgba[i + 1] = (uint8_t)(g + (rgba[i + 1] * ia + 127) / 255);
            rgba[i + 2] = (uint8_t)(b + (rgba[i + 2] * ia + 127) / 255);
            rgba[i + 3] = (uint8_t)(a + (rgba[i + 3] * ia + 127) / 255);
        }
    }
}

// The clipboard is the Java framework's; not reached from here yet.
void cwindow_set_clipboard_text(const char* text) { (void)text; }

int32_t cwindow_clipboard_text(char* buf, int32_t cap) {
    if (buf != NULL && cap > 0)
        buf[0] = 0;
    return 0;
}

uint64_t cwindow_native_window(int32_t window) {
    (void)window;
    return (uint64_t)(uintptr_t)nativeWindow;
}

uint64_t cwindow_native_view(int32_t window) { return cwindow_native_window(window); }
