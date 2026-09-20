// cwindow: a platform's window system, as a C ABI the window target calls.
//
// It is the only part of ui/window that knows what an NSWindow is. Every
// call is scalar -- numbers, and text as NUL-terminated UTF-8 -- so the
// Vertex side needs nothing from this header but the symbols.
//
// A window is an id, positive, or a negative error. Events are queued per
// window: cwindow_next moves the next one into the window's current slot
// and the cwindow_event_* calls read that slot.
//
// Waiting is not done here. Each window has a descriptor that is readable
// while its queue is not empty, and the caller waits on that however it
// waits on descriptors -- ui/window awaits it, so that a task waiting for
// an event gives up its thread. What cwindow does own is the thread's
// idle wait: the window system only delivers anything from inside its own
// event wait, so cwindow installs that as the executor's. See
// vertex_task_set_idle_wait.
#pragma once

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

enum {
    CWINDOW_OK                = 0,
    CWINDOW_ERR_UNSUPPORTED   = -1,   // no window system on this platform
    CWINDOW_ERR_NO_DISPLAY    = -2,   // no session to show a window in
    CWINDOW_ERR_INVALID       = -3,   // no such window, or an argument out of range
    CWINDOW_ERR_SYSTEM        = -4
};

// Creation flags.
enum {
    CWINDOW_RESIZABLE = 1,
    CWINDOW_DECORATED = 2,
    CWINDOW_VISIBLE   = 4
};

// Event kinds, as cwindow_next returns them. 0 is "none queued".
enum {
    CWINDOW_EVENT_NONE               = 0,
    CWINDOW_EVENT_CLOSE_REQUESTED    = 1,
    CWINDOW_EVENT_FOCUS_CHANGED      = 2,   // code: 1 focused, 0 not
    CWINDOW_EVENT_RESIZED            = 3,   // x, y: size in points
    CWINDOW_EVENT_MOVED              = 4,   // x, y: position in points
    CWINDOW_EVENT_SCALE_CHANGED      = 5,   // x: scale factor
    CWINDOW_EVENT_POINTER_MOVED      = 6,   // x, y; pressure; flags: pointer kind
    CWINDOW_EVENT_POINTER_DOWN       = 7,   // as moved; code: button
    CWINDOW_EVENT_POINTER_UP         = 8,   // as moved; code: button
    CWINDOW_EVENT_POINTER_LEFT       = 9,
    CWINDOW_EVENT_SCROLLED           = 10,  // x, y: delta; code: 1 precise (points), 0 lines
    CWINDOW_EVENT_KEY_DOWN           = 11,  // code: key code; modifiers; flags: 1 repeat; text: key
    CWINDOW_EVENT_KEY_UP             = 12,  // as key down
    CWINDOW_EVENT_TEXT               = 13,  // text: committed characters
    CWINDOW_EVENT_COMPOSITION        = 14,  // text: characters being composed, "" when it ends
    CWINDOW_EVENT_FRAME              = 15,  // time, interval: seconds
    CWINDOW_EVENT_THEME_CHANGED      = 16,  // code: 0 light, 1 dark
    CWINDOW_EVENT_MODIFIERS_CHANGED  = 17   // modifiers
};

// Modifier bits.
enum {
    CWINDOW_MOD_SHIFT   = 1,
    CWINDOW_MOD_CONTROL = 2,
    CWINDOW_MOD_ALT     = 4,
    CWINDOW_MOD_META    = 8,
    CWINDOW_MOD_CAPS    = 16
};

int32_t cwindow_create(const char* title, double width, double height, int32_t flags);
void    cwindow_close(int32_t window);

// Readable while the window has an event queued.
int32_t cwindow_descriptor(int32_t window);

int32_t cwindow_next(int32_t window);
int32_t cwindow_event_code(int32_t window);
int32_t cwindow_event_modifiers(int32_t window);
int32_t cwindow_event_flags(int32_t window);
double  cwindow_event_x(int32_t window);
double  cwindow_event_y(int32_t window);
double  cwindow_event_pressure(int32_t window);
double  cwindow_event_time(int32_t window);
double  cwindow_event_interval(int32_t window);
// Copies the current event's text, NUL-terminated, into buf, and is the
// number of bytes it has without the NUL -- which may be more than cap.
int32_t cwindow_event_text(int32_t window, char* buf, int32_t cap);

double  cwindow_width(int32_t window);          // points
double  cwindow_height(int32_t window);
int32_t cwindow_pixel_width(int32_t window);    // device pixels
int32_t cwindow_pixel_height(int32_t window);
double  cwindow_scale(int32_t window);
int32_t cwindow_theme(int32_t window);          // 0 light, 1 dark
int32_t cwindow_focused(int32_t window);

void    cwindow_set_title(int32_t window, const char* title);
void    cwindow_set_size(int32_t window, double width, double height);
void    cwindow_set_min_size(int32_t window, double width, double height);
void    cwindow_set_visible(int32_t window, int32_t visible);
void    cwindow_set_fullscreen(int32_t window, int32_t fullscreen);
void    cwindow_set_cursor(int32_t window, int32_t cursor);

// Asks for one CWINDOW_EVENT_FRAME, at the display's next refresh.
void    cwindow_request_frame(int32_t window);

// Shows width x height RGBA8 pixels, top row first.
int32_t cwindow_present(int32_t window, const uint8_t* rgba, int32_t width, int32_t height);

// Typography & text rasterization via platform CoreText / CoreGraphics.
void    cwindow_measure_text(const char* text, double font_size, int32_t bold, int32_t italic, double* out_w, double* out_h);
void    cwindow_draw_text(uint8_t* rgba, int32_t buf_w, int32_t buf_h,
                          int32_t x, int32_t y, const char* text,
                          double font_size, int32_t bold, int32_t italic,
                          uint8_t r, uint8_t g, uint8_t b, uint8_t a,
                          double scale,
                          int32_t clip_x, int32_t clip_y, int32_t clip_w, int32_t clip_h);

// High-performance SIMD rectangle fill into RGBA8 buffer.
void    cwindow_fill_rect(uint8_t* rgba, int32_t buf_w, int32_t buf_h,
                          int32_t x, int32_t y, int32_t w, int32_t h,
                          uint8_t r, uint8_t g, uint8_t b, uint8_t a,
                          int32_t clip_x, int32_t clip_y, int32_t clip_w, int32_t clip_h);

// The system clipboard's text. Setting replaces it; getting copies it,
// NUL-terminated, into buf and answers the number of bytes without the
// NUL, which may be more than cap; 0 where the clipboard holds no text.
void    cwindow_set_clipboard_text(const char* text);
int32_t cwindow_clipboard_text(char* buf, int32_t cap);

// The native objects, for a renderer binding its own swapchain.
uint64_t cwindow_native_window(int32_t window);
uint64_t cwindow_native_view(int32_t window);

#ifdef __cplusplus
}
#endif

