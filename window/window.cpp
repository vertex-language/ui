// A platform's window system, for package ui/window: window_darwin.mm
// (AppKit) and window_android.cpp (NativeActivity).
//
// It is the only part of ui/window that knows what an NSWindow is. Every
// call is scalar -- numbers, and text as NUL-terminated UTF-8.
//
// A window is an id, positive, or a negative error. Events are queued per
// window: winNext moves the next one into the window's current slot
// and the winEvent* calls read that slot.
//
// Waiting is not done here. Each window has a descriptor that is readable
// while its queue is not empty, and the caller waits on that however it
// waits on descriptors -- ui/window awaits it, so that a task waiting for
// an event gives up its thread. What this does own is the thread's
// idle wait: the window system only delivers anything from inside its own
// event wait, so window_darwin.mm installs that as the executor's. See
// vertex_task_set_idle_wait.
module;
#include <stdint.h>
#if defined(__APPLE__)
#pragma vertex framework("Cocoa")
#pragma vertex framework("QuartzCore")
#pragma vertex framework("CoreText")
#endif
export module ui.window;

// Error codes, negative, as every call that can fail returns them.
export namespace Err {
    constexpr int32_t ok = 0;
    constexpr int32_t unsupported = -1;  // no window system on this platform
    constexpr int32_t noDisplay = -2;  // no session to show a window in
    constexpr int32_t invalid = -3;  // no such window, or an argument out of range
    constexpr int32_t system = -4;
}

// Creation flags.
export namespace CreateFlag {
    constexpr int32_t resizable = 1;
    constexpr int32_t decorated = 2;
    constexpr int32_t visible = 4;
}

// Event kinds, as winNext returns them. 0 is "none queued".
export namespace EventKind {
    constexpr int32_t none = 0;
    constexpr int32_t closeRequested = 1;
    constexpr int32_t focusChanged = 2;  // code: 1 focused, 0 not
    constexpr int32_t resized = 3;  // x, y: size in points
    constexpr int32_t moved = 4;  // x, y: position in points
    constexpr int32_t scaleChanged = 5;  // x: scale factor
    constexpr int32_t pointerMoved = 6;  // x, y; pressure; flags: pointer kind, click count << 8 on down and up
    constexpr int32_t pointerDown = 7;  // as moved; code: button
    constexpr int32_t pointerUp = 8;  // as moved; code: button
    constexpr int32_t pointerLeft = 9;
    constexpr int32_t scrolled = 10;  // x, y: delta; code: 1 precise (points), 0 lines
    constexpr int32_t keyDown = 11;  // code: key code; modifiers; flags: 1 repeat; text: key
    constexpr int32_t keyUp = 12;  // as key down
    constexpr int32_t text = 13;  // text: committed characters
    constexpr int32_t composition = 14;  // text: characters being composed, "" when it ends
    constexpr int32_t frame = 15;  // time, interval: seconds
    constexpr int32_t themeChanged = 16;  // code: 0 light, 1 dark
    constexpr int32_t modifiersChanged = 17;  // modifiers
}

// Modifier bits.
export namespace Mod {
    constexpr int32_t shift = 1;
    constexpr int32_t control = 2;
    constexpr int32_t alt = 4;
    constexpr int32_t meta = 8;
    constexpr int32_t caps = 16;
}

export int32_t winCreate(const char* title, double width, double height, int32_t flags) noexcept;
export void winClose(int32_t window) noexcept;

// Readable while the window has an event queued.
export int32_t winDescriptor(int32_t window) noexcept;
export int32_t winNext(int32_t window) noexcept;
export int32_t winEventCode(int32_t window) noexcept;
export int32_t winEventModifiers(int32_t window) noexcept;
export int32_t winEventFlags(int32_t window) noexcept;
export double winEventX(int32_t window) noexcept;
export double winEventY(int32_t window) noexcept;
export double winEventPressure(int32_t window) noexcept;
export double winEventTime(int32_t window) noexcept;
export double winEventInterval(int32_t window) noexcept;

// Copies the current event's text, NUL-terminated, into buf, and is the
// number of bytes it has without the NUL -- which may be more than cap.
export int32_t winEventText(int32_t window, char* buf, int32_t cap) noexcept;

export double winWidth(int32_t window) noexcept; // points
export double winHeight(int32_t window) noexcept;
export int32_t winPixelWidth(int32_t window) noexcept; // device pixels
export int32_t winPixelHeight(int32_t window) noexcept;
export double winScale(int32_t window) noexcept;
export int32_t winTheme(int32_t window) noexcept; // 0 light, 1 dark
export int32_t winFocused(int32_t window) noexcept;

export void winSetTitle(int32_t window, const char* title) noexcept;
export void winSetSize(int32_t window, double width, double height) noexcept;
export void winSetMinSize(int32_t window, double width, double height) noexcept;
export void winSetVisible(int32_t window, int32_t visible) noexcept;
export void winSetFullscreen(int32_t window, int32_t fullscreen) noexcept;
export void winSetCursor(int32_t window, int32_t cursor) noexcept; // 6: hidden

// A cursor from width x height premultiplied RGBA8 pixels, top row first,
// scale pixels per point, with its hot spot in pixels. Kept until the next
// winSetCursor.
export int32_t winSetCursorImage(int32_t window, const uint8_t* rgba, int32_t width, int32_t height,
                                 int32_t hotX, int32_t hotY, double scale) noexcept;

// Asks for one EventKind::frame, at the display's next refresh.
export void winRequestFrame(int32_t window) noexcept;

// Shows width x height RGBA8 pixels, top row first.
export int32_t winPresent(int32_t window, const uint8_t* rgba, int32_t width,
                          int32_t height) noexcept;

// Typography & text rasterization via platform CoreText / CoreGraphics.
export void winMeasureText(const char* text, double font_size, int32_t bold, int32_t italic,
                           double* out_w, double* out_h) noexcept;
export void winDrawText(uint8_t* rgba, int32_t buf_w, int32_t buf_h, int32_t x, int32_t y,
                        const char* text, double font_size, int32_t bold, int32_t italic, uint8_t r,
                        uint8_t g, uint8_t b, uint8_t a, double scale, int32_t clip_x,
                        int32_t clip_y, int32_t clip_w, int32_t clip_h) noexcept;

// High-performance SIMD rectangle fill into RGBA8 buffer.
export void winFillRect(uint8_t* rgba, int32_t buf_w, int32_t buf_h, int32_t x, int32_t y,
                        int32_t w, int32_t h, uint8_t r, uint8_t g, uint8_t b, uint8_t a,
                        int32_t clip_x, int32_t clip_y, int32_t clip_w, int32_t clip_h) noexcept;

// The system clipboard's text. Setting replaces it; getting copies it,
// NUL-terminated, into buf and answers the number of bytes without the
// NUL, which may be more than cap; 0 where the clipboard holds no text.
export void winSetClipboardText(const char* text) noexcept;
export int32_t winClipboardText(char* buf, int32_t cap) noexcept;

// The native objects, for a renderer binding its own swapchain.
export uint64_t winNativeWindow(int32_t window) noexcept;
export uint64_t winNativeView(int32_t window) noexcept;
