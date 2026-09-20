// cfont: the platform's fonts, as a C ABI the font target calls.
//
// It is the only part of ui/font that knows what a CTFont is. A face is
// an id, positive, or a negative error; it names a font at one size. The
// Vertex side asks a face to shape text into glyphs and advances, and
// asks for any glyph's coverage mask at a scale, and caches both.
#pragma once

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// A face for a family at a size, in CSS terms: weight 100 to 900, italic
// 0 or 1. The generic families (serif, sans-serif, monospace, system-ui,
// cursive, fantasy) name the platform's choice for each; any other name
// is looked up, and is -1 where no installed family has it.
int32_t cfont_face(const char* family, double size, int32_t weight, int32_t italic);

// Registers a font file with the system for this process, so that its
// family can be asked for by name. Copies that family name, as the
// file spells it, NUL-terminated, into family (up to cap bytes), and
// answers 1, or 0 where the file is not a font it can read.
int32_t cfont_register(const char* path, char* family, int32_t cap);

// The face's metrics at its size, in CSS pixels: ascent and descent are
// positive distances from the baseline; the advance is a space's.
void cfont_metrics(int32_t face, double* ascent, double* descent, double* leading,
                   double* x_height, double* space_advance);

// Shapes UTF-8 text with a face into glyphs. Each glyph is on some face --
// the one asked for, or one the system fell back to for a character it
// lacks, which gets an id of its own -- and has an advance in CSS pixels.
// Fills up to cap entries and answers how many the text has, which may
// be more: call again with room for them.
int32_t cfont_shape(int32_t face, const char* text, int32_t len,
                    uint32_t* glyphs, int32_t* faces, float* advances, int32_t cap);

// A glyph's coverage at scale device pixels per CSS pixel: an 8-bit mask
// of width x height rows, top row first, whose top-left corner sits left
// pixels right of and top pixels above the glyph's origin on the
// baseline. Writes up to cap bytes and answers how many the mask has.
int32_t cfont_glyph(int32_t face, uint32_t glyph, double scale,
                    int32_t* left, int32_t* top, int32_t* width, int32_t* height,
                    uint8_t* buf, int32_t cap);

#ifdef __cplusplus
}
#endif
