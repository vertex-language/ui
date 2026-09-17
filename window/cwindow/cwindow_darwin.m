// cwindow on macOS: AppKit.
//
// Everything runs on the main thread, which is the thread the Vertex
// executor runs on. AppKit delivers events only from inside its own wait,
// so this file installs that wait as the executor's idle wait: when no task
// can run, the thread sleeps in -[NSApplication nextEventMatchingMask:...],
// as a native app's does, and comes back out for a window event, a
// descriptor some task waits on becoming ready, or the next deadline.
#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>
#include <fcntl.h>
#include <unistd.h>
#include <string.h>

#include "cwindow.h"

extern void    vertex_task_set_idle_wait(void (*wait)(int64_t timeoutNanos));
extern int32_t vertex_task_io_descriptor(void);

// ---- events ----

typedef struct {
    int32_t kind;
    int32_t code;
    int32_t modifiers;
    int32_t flags;
    double  x, y, pressure, time, interval;
    char*   text;   // malloc'd, or NULL
} Event;

static void eventFree(Event* e) {
    free(e->text);
    e->text = NULL;
}

static char* copyText(NSString* s) {
    if (s == nil)
        return strdup("");
    const char* utf8 = [s UTF8String];
    return strdup(utf8 != NULL ? utf8 : "");
}

// ---- key codes ----
//
// macOS virtual key codes (kVK_*) to ui/window's KeyCode numbering, which
// is window/key.vs's. Where a key is on the keyboard, whatever it means.
static int32_t keyCodeFor(unsigned short vk) {
    switch (vk) {
    case 0x00: return 1;   // a
    case 0x0B: return 2;   // b
    case 0x08: return 3;   // c
    case 0x02: return 4;   // d
    case 0x0E: return 5;   // e
    case 0x03: return 6;   // f
    case 0x05: return 7;   // g
    case 0x04: return 8;   // h
    case 0x22: return 9;   // i
    case 0x26: return 10;  // j
    case 0x28: return 11;  // k
    case 0x25: return 12;  // l
    case 0x2E: return 13;  // m
    case 0x2D: return 14;  // n
    case 0x1F: return 15;  // o
    case 0x23: return 16;  // p
    case 0x0C: return 17;  // q
    case 0x0F: return 18;  // r
    case 0x01: return 19;  // s
    case 0x11: return 20;  // t
    case 0x20: return 21;  // u
    case 0x09: return 22;  // v
    case 0x0D: return 23;  // w
    case 0x07: return 24;  // x
    case 0x10: return 25;  // y
    case 0x06: return 26;  // z
    case 0x1D: return 27;  // 0
    case 0x12: return 28;  // 1
    case 0x13: return 29;  // 2
    case 0x14: return 30;  // 3
    case 0x15: return 31;  // 4
    case 0x17: return 32;  // 5
    case 0x16: return 33;  // 6
    case 0x1A: return 34;  // 7
    case 0x1C: return 35;  // 8
    case 0x19: return 36;  // 9
    case 0x35: return 40;  // escape
    case 0x24: return 41;  // enter
    case 0x30: return 42;  // tab
    case 0x31: return 43;  // space
    case 0x33: return 44;  // backspace
    case 0x75: return 45;  // delete
    case 0x7B: return 46;  // arrowLeft
    case 0x7C: return 47;  // arrowRight
    case 0x7E: return 48;  // arrowUp
    case 0x7D: return 49;  // arrowDown
    case 0x73: return 50;  // home
    case 0x77: return 51;  // end
    case 0x74: return 52;  // pageUp
    case 0x79: return 53;  // pageDown
    case 0x38: return 60;  // shiftLeft
    case 0x3C: return 61;  // shiftRight
    case 0x3B: return 62;  // controlLeft
    case 0x3E: return 63;  // controlRight
    case 0x3A: return 64;  // altLeft
    case 0x3D: return 65;  // altRight
    case 0x37: return 66;  // metaLeft
    case 0x36: return 67;  // metaRight
    case 0x39: return 68;  // capsLock
    case 0x7A: return 70;  // f1
    case 0x78: return 71;  // f2
    case 0x63: return 72;  // f3
    case 0x76: return 73;  // f4
    case 0x60: return 74;  // f5
    case 0x61: return 75;  // f6
    case 0x62: return 76;  // f7
    case 0x64: return 77;  // f8
    case 0x65: return 78;  // f9
    case 0x6D: return 79;  // f10
    case 0x67: return 80;  // f11
    case 0x6F: return 81;  // f12
    case 0x1B: return 90;  // minus
    case 0x18: return 91;  // equal
    case 0x21: return 92;  // bracketLeft
    case 0x1E: return 93;  // bracketRight
    case 0x2A: return 94;  // backslash
    case 0x29: return 95;  // semicolon
    case 0x27: return 96;  // quote
    case 0x32: return 97;  // backquote
    case 0x2B: return 98;  // comma
    case 0x2F: return 99;  // period
    case 0x2C: return 100; // slash
    }
    return 0;
}

// The W3C key value for a key that does not type a character, or nil.
static NSString* namedKey(int32_t code) {
    switch (code) {
    case 40: return @"Escape";
    case 41: return @"Enter";
    case 42: return @"Tab";
    case 44: return @"Backspace";
    case 45: return @"Delete";
    case 46: return @"ArrowLeft";
    case 47: return @"ArrowRight";
    case 48: return @"ArrowUp";
    case 49: return @"ArrowDown";
    case 50: return @"Home";
    case 51: return @"End";
    case 52: return @"PageUp";
    case 53: return @"PageDown";
    case 60: case 61: return @"Shift";
    case 62: case 63: return @"Control";
    case 64: case 65: return @"Alt";
    case 66: case 67: return @"Meta";
    case 68: return @"CapsLock";
    }
    if (code >= 70 && code <= 81)
        return [NSString stringWithFormat:@"F%d", (int)(code - 69)];
    return nil;
}

static int32_t modifiersFor(NSEventModifierFlags f) {
    int32_t m = 0;
    if (f & NSEventModifierFlagShift) m |= CWINDOW_MOD_SHIFT;
    if (f & NSEventModifierFlagControl) m |= CWINDOW_MOD_CONTROL;
    if (f & NSEventModifierFlagOption) m |= CWINDOW_MOD_ALT;
    if (f & NSEventModifierFlagCommand) m |= CWINDOW_MOD_META;
    if (f & NSEventModifierFlagCapsLock) m |= CWINDOW_MOD_CAPS;
    return m;
}

// ---- windows ----

@class CWView;

@interface CWWindow : NSObject <NSWindowDelegate>
@property (nonatomic, strong) NSWindow* window;
@property (nonatomic, strong) CWView* view;
@property (nonatomic) int32_t ident;
@property (nonatomic) int readFd;
@property (nonatomic) int writeFd;
@property (nonatomic) BOOL signalled;
@property (nonatomic, strong) id displayLink;
@end

static NSMutableDictionary* windows;   // NSNumber id -> CWWindow
static int32_t nextIdent = 1;

// The queue lives outside the object so that events are plain C.
typedef struct {
    Event* items;
    int    count, cap, head;
    Event  current;
} Queue;

static NSMutableDictionary* queues;    // NSNumber id -> NSValue(Queue*)

static Queue* queueOf(int32_t ident) {
    NSValue* v = queues[@(ident)];
    return v != nil ? (Queue*)[v pointerValue] : NULL;
}

static CWWindow* windowOf(int32_t ident) {
    return windows[@(ident)];
}

static void push(CWWindow* w, Event e) {
    Queue* q = queueOf(w.ident);
    if (q == NULL) {
        eventFree(&e);
        return;
    }
    if (q->count == q->cap) {
        int cap = q->cap == 0 ? 32 : q->cap * 2;
        Event* grown = calloc((size_t)cap, sizeof(Event));
        for (int i = 0; i < q->count; i++)
            grown[i] = q->items[(q->head + i) % q->cap];
        free(q->items);
        q->items = grown;
        q->cap = cap;
        q->head = 0;
    }
    q->items[(q->head + q->count) % q->cap] = e;
    q->count++;
    // One byte marks the queue non-empty; cwindow_next drains it when the
    // queue empties again.
    if (!w.signalled) {
        char b = 1;
        (void)write(w.writeFd, &b, 1);
        w.signalled = YES;
    }
}

static void pushKind(CWWindow* w, int32_t kind, int32_t code, double x, double y) {
    Event e = {0};
    e.kind = kind;
    e.code = code;
    e.x = x;
    e.y = y;
    push(w, e);
}

// ---- the view: input, drawing, and text ----

@interface CWView : NSView <NSTextInputClient>
@property (nonatomic, assign) CWWindow* owner;
@property (nonatomic, strong) NSTrackingArea* tracking;
@property (nonatomic, strong) NSString* marked;
@end

@implementation CWView

- (BOOL)isFlipped { return YES; }
- (BOOL)acceptsFirstResponder { return YES; }
- (BOOL)acceptsFirstMouse:(NSEvent*)event { return YES; }
- (BOOL)wantsUpdateLayer { return YES; }

- (void)updateTrackingAreas {
    if (self.tracking != nil)
        [self removeTrackingArea:self.tracking];
    self.tracking = [[NSTrackingArea alloc]
        initWithRect:NSZeroRect
             options:NSTrackingMouseMoved | NSTrackingMouseEnteredAndExited |
                     NSTrackingActiveAlways | NSTrackingInVisibleRect
               owner:self
            userInfo:nil];
    [self addTrackingArea:self.tracking];
    [super updateTrackingAreas];
}

- (void)pointer:(NSEvent*)event kind:(int32_t)kind button:(int32_t)button {
    NSPoint p = [self convertPoint:[event locationInWindow] fromView:nil];
    Event e = {0};
    e.kind = kind;
    e.code = button;
    e.x = p.x;
    e.y = p.y;
    e.modifiers = modifiersFor([event modifierFlags]);
    e.flags = [event subtype] == NSEventSubtypeTabletPoint ? 1 : 0;
    e.pressure = e.flags == 1 ? [event pressure] : 0;
    push(self.owner, e);
}

- (void)mouseMoved:(NSEvent*)e { [self pointer:e kind:CWINDOW_EVENT_POINTER_MOVED button:0]; }
- (void)mouseDragged:(NSEvent*)e { [self pointer:e kind:CWINDOW_EVENT_POINTER_MOVED button:0]; }
- (void)rightMouseDragged:(NSEvent*)e { [self pointer:e kind:CWINDOW_EVENT_POINTER_MOVED button:0]; }
- (void)otherMouseDragged:(NSEvent*)e { [self pointer:e kind:CWINDOW_EVENT_POINTER_MOVED button:0]; }
- (void)mouseDown:(NSEvent*)e { [self pointer:e kind:CWINDOW_EVENT_POINTER_DOWN button:0]; }
- (void)mouseUp:(NSEvent*)e { [self pointer:e kind:CWINDOW_EVENT_POINTER_UP button:0]; }
- (void)rightMouseDown:(NSEvent*)e { [self pointer:e kind:CWINDOW_EVENT_POINTER_DOWN button:1]; }
- (void)rightMouseUp:(NSEvent*)e { [self pointer:e kind:CWINDOW_EVENT_POINTER_UP button:1]; }
- (void)otherMouseDown:(NSEvent*)e {
    [self pointer:e kind:CWINDOW_EVENT_POINTER_DOWN button:(int32_t)[e buttonNumber]];
}
- (void)otherMouseUp:(NSEvent*)e {
    [self pointer:e kind:CWINDOW_EVENT_POINTER_UP button:(int32_t)[e buttonNumber]];
}
- (void)mouseExited:(NSEvent*)e { pushKind(self.owner, CWINDOW_EVENT_POINTER_LEFT, 0, 0, 0); }

- (void)scrollWheel:(NSEvent*)event {
    Event e = {0};
    e.kind = CWINDOW_EVENT_SCROLLED;
    e.code = [event hasPreciseScrollingDeltas] ? 1 : 0;
    e.x = [event scrollingDeltaX];
    e.y = [event scrollingDeltaY];
    e.modifiers = modifiersFor([event modifierFlags]);
    push(self.owner, e);
}

- (void)key:(NSEvent*)event kind:(int32_t)kind {
    Event e = {0};
    e.kind = kind;
    e.code = keyCodeFor([event keyCode]);
    e.modifiers = modifiersFor([event modifierFlags]);
    e.flags = [event isARepeat] ? 1 : 0;
    NSString* key = namedKey(e.code);
    if (key == nil)
        key = [event charactersIgnoringModifiers];
    e.text = copyText(key);
    push(self.owner, e);
}

- (void)keyDown:(NSEvent*)event {
    [self key:event kind:CWINDOW_EVENT_KEY_DOWN];
    // And through the input system, which is what turns key presses into
    // text: dead keys, input methods, and everything else a layout does.
    [self interpretKeyEvents:@[ event ]];
}

- (void)keyUp:(NSEvent*)event { [self key:event kind:CWINDOW_EVENT_KEY_UP]; }

- (void)flagsChanged:(NSEvent*)event {
    Event e = {0};
    e.kind = CWINDOW_EVENT_MODIFIERS_CHANGED;
    e.modifiers = modifiersFor([event modifierFlags]);
    push(self.owner, e);
}

- (void)viewDidChangeEffectiveAppearance {
    [super viewDidChangeEffectiveAppearance];
    pushKind(self.owner, CWINDOW_EVENT_THEME_CHANGED, cwindow_theme(self.owner.ident), 0, 0);
}

- (void)onFrame:(id)link {
    CADisplayLink* l = (CADisplayLink*)link;
    Event e = {0};
    e.kind = CWINDOW_EVENT_FRAME;
    e.time = [l targetTimestamp];
    e.interval = [l targetTimestamp] - [l timestamp];
    push(self.owner, e);
    [l setPaused:YES];
}

// NSTextInputClient

- (void)insertText:(id)string replacementRange:(NSRange)range {
    NSString* s = [string isKindOfClass:[NSAttributedString class]] ? [string string] : string;
    if (self.marked != nil) {
        self.marked = nil;
        Event end = {0};
        end.kind = CWINDOW_EVENT_COMPOSITION;
        end.text = copyText(@"");
        push(self.owner, end);
    }
    Event e = {0};
    e.kind = CWINDOW_EVENT_TEXT;
    e.text = copyText(s);
    push(self.owner, e);
}

- (void)setMarkedText:(id)string selectedRange:(NSRange)sel replacementRange:(NSRange)rep {
    NSString* s = [string isKindOfClass:[NSAttributedString class]] ? [string string] : string;
    self.marked = [s length] > 0 ? s : nil;
    Event e = {0};
    e.kind = CWINDOW_EVENT_COMPOSITION;
    e.text = copyText(s);
    push(self.owner, e);
}

- (void)unmarkText {
    if (self.marked == nil)
        return;
    self.marked = nil;
    Event e = {0};
    e.kind = CWINDOW_EVENT_COMPOSITION;
    e.text = copyText(@"");
    push(self.owner, e);
}

- (BOOL)hasMarkedText { return self.marked != nil; }
- (NSRange)markedRange {
    if (self.marked != nil)
        return NSMakeRange(0, [self.marked length]);
    return NSMakeRange(NSNotFound, 0);
}
- (NSRange)selectedRange { return NSMakeRange(NSNotFound, 0); }
- (NSAttributedString*)attributedSubstringForProposedRange:(NSRange)r actualRange:(NSRangePointer)a {
    return nil;
}
- (NSArray<NSAttributedStringKey>*)validAttributesForMarkedText { return @[]; }
- (NSRect)firstRectForCharacterRange:(NSRange)r actualRange:(NSRangePointer)a {
    NSRect frame = [self.window convertRectToScreen:[self convertRect:[self bounds] toView:nil]];
    return NSMakeRect(frame.origin.x, frame.origin.y, 0, 0);
}
- (NSUInteger)characterIndexForPoint:(NSPoint)p { return NSNotFound; }
- (void)doCommandBySelector:(SEL)selector {
    // Enter, arrows and the rest arrive as key events; nothing to do here,
    // and doing nothing is what stops the beep.
}

@end

@implementation CWWindow

- (BOOL)windowShouldClose:(NSWindow*)sender {
    // A request: the program decides, by calling Close or not.
    pushKind(self, CWINDOW_EVENT_CLOSE_REQUESTED, 0, 0, 0);
    return NO;
}

- (void)windowDidResize:(NSNotification*)n {
    NSSize s = [self.view bounds].size;
    pushKind(self, CWINDOW_EVENT_RESIZED, 0, s.width, s.height);
}

- (void)windowDidMove:(NSNotification*)n {
    NSRect f = [self.window frame];
    NSRect screen = [[self.window screen] frame];
    // Top-left, in points, measured down from the top of the screen.
    pushKind(self, CWINDOW_EVENT_MOVED, 0, f.origin.x, NSMaxY(screen) - NSMaxY(f));
}

- (void)windowDidChangeBackingProperties:(NSNotification*)n {
    pushKind(self, CWINDOW_EVENT_SCALE_CHANGED, 0, [self.window backingScaleFactor], 0);
}

- (void)windowDidBecomeKey:(NSNotification*)n {
    pushKind(self, CWINDOW_EVENT_FOCUS_CHANGED, 1, 0, 0);
}

- (void)windowDidResignKey:(NSNotification*)n {
    pushKind(self, CWINDOW_EVENT_FOCUS_CHANGED, 0, 0, 0);
}

@end

// ---- the application, and the thread's wait ----

@interface CWAppDelegate : NSObject <NSApplicationDelegate>
@end

@implementation CWAppDelegate
- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication*)sender {
    // Quit is a close request to every window, which the program answers.
    for (NSNumber* key in [windows allKeys])
        pushKind(windows[key], CWINDOW_EVENT_CLOSE_REQUESTED, 0, 0, 0);
    return NSTerminateCancel;
}
@end

static CWAppDelegate* appDelegate;
static CFFileDescriptorRef ioWatch;
static const short wakeSubtype = 0x5657;

// A descriptor a task waits on became ready: wake AppKit's wait, so that
// the executor gets the thread back.
static void ioReady(CFFileDescriptorRef f, CFOptionFlags types, void* info) {
    NSEvent* wake = [NSEvent otherEventWithType:NSEventTypeApplicationDefined
                                       location:NSZeroPoint
                                  modifierFlags:0
                                      timestamp:0
                                   windowNumber:0
                                        context:nil
                                        subtype:wakeSubtype
                                          data1:0
                                          data2:0];
    [NSApp postEvent:wake atStart:YES];
}

static void idleWait(int64_t timeout) {
    @autoreleasepool {
        if (ioWatch != NULL)
            CFFileDescriptorEnableCallBacks(ioWatch, kCFFileDescriptorReadCallBack);
        NSDate* until;
        if (timeout < 0)
            until = [NSDate distantFuture];
        else if (timeout == 0)
            until = [NSDate distantPast];
        else
            until = [NSDate dateWithTimeIntervalSinceNow:(double)timeout / 1e9];
        NSEvent* event = [NSApp nextEventMatchingMask:NSEventMaskAny
                                            untilDate:until
                                               inMode:NSDefaultRunLoopMode
                                              dequeue:YES];
        while (event != nil) {
            BOOL wake = [event type] == NSEventTypeApplicationDefined && [event subtype] == wakeSubtype;
            if (!wake)
                [NSApp sendEvent:event];
            event = [NSApp nextEventMatchingMask:NSEventMaskAny
                                       untilDate:[NSDate distantPast]
                                          inMode:NSDefaultRunLoopMode
                                         dequeue:YES];
        }
    }
}

static void menuBar(void) {
    NSMenu* bar = [[NSMenu alloc] init];
    NSMenuItem* appItem = [[NSMenuItem alloc] init];
    [bar addItem:appItem];
    NSMenu* appMenu = [[NSMenu alloc] init];
    NSString* name = [[NSProcessInfo processInfo] processName];
    [appMenu addItemWithTitle:[@"Quit " stringByAppendingString:name]
                       action:@selector(terminate:)
                keyEquivalent:@"q"];
    [appItem setSubmenu:appMenu];
    [NSApp setMainMenu:bar];
}

// Brings up the application the first time a window is made.
static BOOL started(void) {
    if (windows != nil)
        return YES;
    if (![NSThread isMainThread])
        return NO;
    windows = [NSMutableDictionary dictionary];
    queues = [NSMutableDictionary dictionary];
    [NSApplication sharedApplication];
    appDelegate = [[CWAppDelegate alloc] init];
    [NSApp setDelegate:appDelegate];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    menuBar();
    [NSApp finishLaunching];
    [NSApp activateIgnoringOtherApps:YES];

    int fd = vertex_task_io_descriptor();
    if (fd >= 0) {
        ioWatch = CFFileDescriptorCreate(kCFAllocatorDefault, fd, false, ioReady, NULL);
        CFRunLoopSourceRef src = CFFileDescriptorCreateRunLoopSource(kCFAllocatorDefault, ioWatch, 0);
        CFRunLoopAddSource(CFRunLoopGetMain(), src, kCFRunLoopCommonModes);
        CFRelease(src);
    }
    vertex_task_set_idle_wait(idleWait);
    return YES;
}

// ---- the C ABI ----

int32_t cwindow_create(const char* title, double width, double height, int32_t flags) {
    @autoreleasepool {
        if (!started())
            return CWINDOW_ERR_NO_DISPLAY;
        if (width <= 0 || height <= 0)
            return CWINDOW_ERR_INVALID;

        int fds[2];
        if (pipe(fds) != 0)
            return CWINDOW_ERR_SYSTEM;
        fcntl(fds[0], F_SETFL, O_NONBLOCK);
        fcntl(fds[1], F_SETFL, O_NONBLOCK);

        NSWindowStyleMask style = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                                  NSWindowStyleMaskMiniaturizable;
        if (flags & CWINDOW_RESIZABLE)
            style |= NSWindowStyleMaskResizable;
        if (!(flags & CWINDOW_DECORATED))
            style = NSWindowStyleMaskBorderless | (style & NSWindowStyleMaskResizable);

        NSWindow* nsw = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, width, height)
                                                    styleMask:style
                                                      backing:NSBackingStoreBuffered
                                                        defer:NO];
        [nsw setReleasedWhenClosed:NO];
        [nsw setTitle:[NSString stringWithUTF8String:title != NULL ? title : ""]];
        [nsw setAcceptsMouseMovedEvents:YES];
        [nsw center];

        CWWindow* w = [[CWWindow alloc] init];
        w.ident = nextIdent++;
        w.window = nsw;
        w.readFd = fds[0];
        w.writeFd = fds[1];

        CWView* view = [[CWView alloc] initWithFrame:NSMakeRect(0, 0, width, height)];
        view.owner = w;
        [view setWantsLayer:YES];
        [[view layer] setContentsGravity:kCAGravityTopLeft];
        w.view = view;
        [nsw setContentView:view];
        [nsw setDelegate:w];
        [nsw makeFirstResponder:view];

        Queue* q = calloc(1, sizeof(Queue));
        queues[@(w.ident)] = [NSValue valueWithPointer:q];
        windows[@(w.ident)] = w;

        if (flags & CWINDOW_VISIBLE)
            [nsw makeKeyAndOrderFront:nil];
        return w.ident;
    }
}

void cwindow_close(int32_t window) {
    @autoreleasepool {
        CWWindow* w = windowOf(window);
        if (w == nil)
            return;
        if (w.displayLink != nil)
            [w.displayLink invalidate];
        [w.window setDelegate:nil];
        [w.window close];
        close(w.readFd);
        close(w.writeFd);
        Queue* q = queueOf(window);
        if (q != NULL) {
            for (int i = 0; i < q->count; i++)
                eventFree(&q->items[(q->head + i) % q->cap]);
            eventFree(&q->current);
            free(q->items);
            free(q);
        }
        [queues removeObjectForKey:@(window)];
        [windows removeObjectForKey:@(window)];
    }
}

int32_t cwindow_descriptor(int32_t window) {
    CWWindow* w = windowOf(window);
    return w != nil ? w.readFd : CWINDOW_ERR_INVALID;
}

int32_t cwindow_next(int32_t window) {
    CWWindow* w = windowOf(window);
    Queue* q = queueOf(window);
    if (w == nil || q == NULL)
        return CWINDOW_ERR_INVALID;
    eventFree(&q->current);
    if (q->count == 0) {
        memset(&q->current, 0, sizeof(Event));
        return CWINDOW_EVENT_NONE;
    }
    q->current = q->items[q->head];
    q->head = (q->head + 1) % q->cap;
    q->count--;
    if (q->count == 0 && w.signalled) {
        char buf[16];
        while (read(w.readFd, buf, sizeof buf) > 0) {
        }
        w.signalled = NO;
    }
    return q->current.kind;
}

static Event* current(int32_t window) {
    Queue* q = queueOf(window);
    return q != NULL ? &q->current : NULL;
}

int32_t cwindow_event_code(int32_t window) { Event* e = current(window); return e ? e->code : 0; }
int32_t cwindow_event_modifiers(int32_t window) { Event* e = current(window); return e ? e->modifiers : 0; }
int32_t cwindow_event_flags(int32_t window) { Event* e = current(window); return e ? e->flags : 0; }
double cwindow_event_x(int32_t window) { Event* e = current(window); return e ? e->x : 0; }
double cwindow_event_y(int32_t window) { Event* e = current(window); return e ? e->y : 0; }
double cwindow_event_pressure(int32_t window) { Event* e = current(window); return e ? e->pressure : 0; }
double cwindow_event_time(int32_t window) { Event* e = current(window); return e ? e->time : 0; }
double cwindow_event_interval(int32_t window) { Event* e = current(window); return e ? e->interval : 0; }

int32_t cwindow_event_text(int32_t window, char* buf, int32_t cap) {
    Event* e = current(window);
    const char* text = (e != NULL && e->text != NULL) ? e->text : "";
    int32_t n = (int32_t)strlen(text);
    if (buf != NULL && cap > 0) {
        int32_t m = n < cap - 1 ? n : cap - 1;
        memcpy(buf, text, (size_t)m);
        buf[m] = 0;
    }
    return n;
}

double cwindow_width(int32_t window) { CWWindow* w = windowOf(window); return w ? [w.view bounds].size.width : 0; }
double cwindow_height(int32_t window) { CWWindow* w = windowOf(window); return w ? [w.view bounds].size.height : 0; }
double cwindow_scale(int32_t window) { CWWindow* w = windowOf(window); return w ? [w.window backingScaleFactor] : 1; }

int32_t cwindow_pixel_width(int32_t window) {
    CWWindow* w = windowOf(window);
    return w ? (int32_t)[w.view convertRectToBacking:[w.view bounds]].size.width : 0;
}

int32_t cwindow_pixel_height(int32_t window) {
    CWWindow* w = windowOf(window);
    return w ? (int32_t)[w.view convertRectToBacking:[w.view bounds]].size.height : 0;
}

int32_t cwindow_theme(int32_t window) {
    CWWindow* w = windowOf(window);
    if (w == nil)
        return 0;
    NSAppearanceName best = [[w.view effectiveAppearance]
        bestMatchFromAppearancesWithNames:@[ NSAppearanceNameAqua, NSAppearanceNameDarkAqua ]];
    return [best isEqualToString:NSAppearanceNameDarkAqua] ? 1 : 0;
}

int32_t cwindow_focused(int32_t window) {
    CWWindow* w = windowOf(window);
    return (w != nil && [w.window isKeyWindow]) ? 1 : 0;
}

void cwindow_set_title(int32_t window, const char* title) {
    CWWindow* w = windowOf(window);
    if (w != nil)
        [w.window setTitle:[NSString stringWithUTF8String:title != NULL ? title : ""]];
}

void cwindow_set_size(int32_t window, double width, double height) {
    CWWindow* w = windowOf(window);
    if (w != nil && width > 0 && height > 0)
        [w.window setContentSize:NSMakeSize(width, height)];
}

void cwindow_set_min_size(int32_t window, double width, double height) {
    CWWindow* w = windowOf(window);
    if (w != nil)
        [w.window setContentMinSize:NSMakeSize(width, height)];
}

void cwindow_set_visible(int32_t window, int32_t visible) {
    CWWindow* w = windowOf(window);
    if (w == nil)
        return;
    if (visible)
        [w.window makeKeyAndOrderFront:nil];
    else
        [w.window orderOut:nil];
}

void cwindow_set_fullscreen(int32_t window, int32_t fullscreen) {
    CWWindow* w = windowOf(window);
    if (w == nil)
        return;
    BOOL now = ([w.window styleMask] & NSWindowStyleMaskFullScreen) != 0;
    if ((fullscreen != 0) != now)
        [w.window toggleFullScreen:nil];
}

void cwindow_request_frame(int32_t window) {
    CWWindow* w = windowOf(window);
    if (w == nil)
        return;
    if (w.displayLink == nil) {
        CADisplayLink* link = [w.view displayLinkWithTarget:w.view selector:@selector(onFrame:)];
        [link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
        w.displayLink = link;
    }
    [(CADisplayLink*)w.displayLink setPaused:NO];
}

static void freePixels(void* info, const void* data, size_t size) {
    free((void*)data);
}

int32_t cwindow_present(int32_t window, const uint8_t* rgba, int32_t width, int32_t height) {
    @autoreleasepool {
        CWWindow* w = windowOf(window);
        if (w == nil || rgba == NULL || width <= 0 || height <= 0)
            return CWINDOW_ERR_INVALID;
        size_t size = (size_t)width * (size_t)height * 4;
        uint8_t* copy = malloc(size);
        if (copy == NULL)
            return CWINDOW_ERR_SYSTEM;
        memcpy(copy, rgba, size);
        CGDataProviderRef provider = CGDataProviderCreateWithData(NULL, copy, size, freePixels);
        CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
        CGImageRef image = CGImageCreate((size_t)width, (size_t)height, 8, 32, (size_t)width * 4, space,
                                         (CGBitmapInfo)kCGImageAlphaPremultipliedLast, provider, NULL,
                                         false, kCGRenderingIntentDefault);
        CGColorSpaceRelease(space);
        CGDataProviderRelease(provider);
        if (image == NULL)
            return CWINDOW_ERR_SYSTEM;
        CALayer* layer = [w.view layer];
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        [layer setContents:(__bridge id)image];
        [layer setContentsScale:[w.window backingScaleFactor]];
        [CATransaction commit];
        CGImageRelease(image);
        return CWINDOW_OK;
    }
}

uint64_t cwindow_native_window(int32_t window) {
    CWWindow* w = windowOf(window);
    return w != nil ? (uint64_t)(uintptr_t)(__bridge void*)w.window : 0;
}

uint64_t cwindow_native_view(int32_t window) {
    CWWindow* w = windowOf(window);
    return w != nil ? (uint64_t)(uintptr_t)(__bridge void*)w.view : 0;
}
