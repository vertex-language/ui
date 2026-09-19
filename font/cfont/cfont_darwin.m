// cfont for macOS: CoreText faces, shaping and glyph masks.
#import <Cocoa/Cocoa.h>
#import <CoreText/CoreText.h>
#include <string.h>
#include "cfont.h"

// Faces are kept for the life of the process: a page uses a handful of
// families at a dozen sizes, and a face is asked for by every word.
static NSMutableArray<id>* faces = nil;   // index + 1 is the id; each is a CTFont
static NSMutableDictionary<NSNumber*, NSMutableDictionary<NSNumber*, id>*>* scaled = nil; // face id -> scale key -> CTFont

static CTFontRef fontOf(int32_t face) {
    if (faces == nil || face <= 0 || face > (int32_t)faces.count)
        return NULL;
    return (__bridge CTFontRef)faces[(NSUInteger)(face - 1)];
}

static int32_t idOf(CTFontRef font) {
    if (faces == nil)
        faces = [NSMutableArray new];
    for (NSUInteger i = 0; i < faces.count; i++) {
        if (CFEqual((__bridge CTFontRef)faces[i], font))
            return (int32_t)i + 1;
    }
    [faces addObject:(__bridge id)font];
    return (int32_t)faces.count;
}

// CSS weights on CoreText's -1 to 1 scale, as AppKit places its named weights.
static CGFloat traitWeight(int32_t weight) {
    if (weight <= 100) return -0.8;
    if (weight <= 200) return -0.6;
    if (weight <= 300) return -0.4;
    if (weight <= 400) return 0.0;
    if (weight <= 500) return 0.23;
    if (weight <= 600) return 0.3;
    if (weight <= 700) return 0.4;
    if (weight <= 800) return 0.56;
    return 0.62;
}

static NSFontWeight systemWeight(int32_t weight) {
    if (weight <= 100) return NSFontWeightUltraLight;
    if (weight <= 200) return NSFontWeightThin;
    if (weight <= 300) return NSFontWeightLight;
    if (weight <= 400) return NSFontWeightRegular;
    if (weight <= 500) return NSFontWeightMedium;
    if (weight <= 600) return NSFontWeightSemibold;
    if (weight <= 700) return NSFontWeightBold;
    if (weight <= 800) return NSFontWeightHeavy;
    return NSFontWeightBlack;
}

static NSString* platformFamily(NSString* family) {
    NSString* lower = [family lowercaseString];
    if ([lower isEqualToString:@"serif"]) return @"Times New Roman";
    if ([lower isEqualToString:@"sans-serif"]) return @"Helvetica Neue";
    if ([lower isEqualToString:@"monospace"]) return @"Menlo";
    if ([lower isEqualToString:@"cursive"]) return @"Snell Roundhand";
    if ([lower isEqualToString:@"fantasy"]) return @"Papyrus";
    if ([lower isEqualToString:@"ui-monospace"]) return @"SF Mono";
    return family;
}

int32_t cfont_face(const char* family, double size, int32_t weight, int32_t italic) {
    if (family == NULL || size <= 0)
        return -1;
    @autoreleasepool {
        NSString* name = [NSString stringWithUTF8String:family];
        if (name == nil)
            return -1;
        NSString* lower = [name lowercaseString];
        NSFont* font = nil;
        if ([lower isEqualToString:@"system-ui"] || [lower isEqualToString:@"-apple-system"] ||
            [lower isEqualToString:@"blinkmacsystemfont"] || [lower isEqualToString:@"ui-sans-serif"]) {
            font = [NSFont systemFontOfSize:size weight:systemWeight(weight)];
            if (italic) {
                NSFontDescriptor* desc = [[font fontDescriptor] fontDescriptorWithSymbolicTraits:NSFontDescriptorTraitItalic];
                NSFont* styled = desc ? [NSFont fontWithDescriptor:desc size:size] : nil;
                if (styled) font = styled;
            }
        } else {
            NSString* wanted = platformFamily(name);
            NSDictionary* traits = @{
                NSFontWeightTrait: @(traitWeight(weight)),
                NSFontSymbolicTrait: @(italic ? NSFontDescriptorTraitItalic : 0),
            };
            NSFontDescriptor* desc = [NSFontDescriptor fontDescriptorWithFontAttributes:@{
                NSFontFamilyAttribute: wanted,
                NSFontTraitsAttribute: traits,
            }];
            NSFontDescriptor* matched = [desc matchingFontDescriptorWithMandatoryKeys:[NSSet setWithObject:NSFontFamilyAttribute]];
            if (matched == nil)
                return -1;
            font = [NSFont fontWithDescriptor:matched size:size];
            if (font == nil)
                return -1;
            // The closest match may not carry the weight or slant; a
            // bold that the family lacks is synthesized by the trait
            // request, which is what browsers do too.
            NSFontDescriptorSymbolicTraits want = 0;
            if (weight >= 600) want |= NSFontDescriptorTraitBold;
            if (italic) want |= NSFontDescriptorTraitItalic;
            if (want != 0) {
                NSFontDescriptor* styledDesc = [[font fontDescriptor] fontDescriptorWithSymbolicTraits:want];
                NSFont* styled = styledDesc ? [NSFont fontWithDescriptor:styledDesc size:size] : nil;
                if (styled) font = styled;
            }
        }
        if (font == nil)
            return -1;
        return idOf((__bridge CTFontRef)font);
    }
}

void cfont_metrics(int32_t face, double* ascent, double* descent, double* leading,
                   double* x_height, double* space_advance) {
    CTFontRef font = fontOf(face);
    if (font == NULL) {
        if (ascent) *ascent = 0;
        if (descent) *descent = 0;
        if (leading) *leading = 0;
        if (x_height) *x_height = 0;
        if (space_advance) *space_advance = 0;
        return;
    }
    if (ascent) *ascent = CTFontGetAscent(font);
    if (descent) *descent = CTFontGetDescent(font);
    if (leading) *leading = CTFontGetLeading(font);
    if (x_height) *x_height = CTFontGetXHeight(font);
    if (space_advance) {
        UniChar space = ' ';
        CGGlyph glyph = 0;
        if (CTFontGetGlyphsForCharacters(font, &space, &glyph, 1)) {
            *space_advance = CTFontGetAdvancesForGlyphs(font, kCTFontOrientationHorizontal, &glyph, NULL, 1);
        } else {
            *space_advance = CTFontGetSize(font) * 0.25;
        }
    }
}

int32_t cfont_shape(int32_t face, const char* text, int32_t len,
                    uint32_t* glyphs, int32_t* faces_out, float* advances, int32_t cap) {
    CTFontRef font = fontOf(face);
    if (font == NULL || text == NULL || len <= 0)
        return 0;
    @autoreleasepool {
        NSString* str = [[NSString alloc] initWithBytes:text length:(NSUInteger)len encoding:NSUTF8StringEncoding];
        if (str == nil || str.length == 0)
            return 0;
        NSDictionary* attrs = @{ (__bridge id)kCTFontAttributeName: (__bridge id)font };
        NSAttributedString* attributed = [[NSAttributedString alloc] initWithString:str attributes:attrs];
        CTLineRef line = CTLineCreateWithAttributedString((__bridge CFAttributedStringRef)attributed);
        if (line == NULL)
            return 0;
        CFArrayRef runs = CTLineGetGlyphRuns(line);
        int32_t total = 0;
        CFIndex nruns = CFArrayGetCount(runs);
        for (CFIndex r = 0; r < nruns; r++) {
            CTRunRef run = (CTRunRef)CFArrayGetValueAtIndex(runs, r);
            CFIndex n = CTRunGetGlyphCount(run);
            if (n <= 0)
                continue;
            CFDictionaryRef runAttrs = CTRunGetAttributes(run);
            CTFontRef runFont = (CTFontRef)CFDictionaryGetValue(runAttrs, kCTFontAttributeName);
            int32_t runFace = face;
            if (runFont != NULL && !CFEqual(runFont, font))
                runFace = idOf(runFont);
            CGGlyph* g = (CGGlyph*)malloc(sizeof(CGGlyph) * (size_t)n);
            CGSize* adv = (CGSize*)malloc(sizeof(CGSize) * (size_t)n);
            CTRunGetGlyphs(run, CFRangeMake(0, n), g);
            CTRunGetAdvances(run, CFRangeMake(0, n), adv);
            for (CFIndex i = 0; i < n; i++) {
                if (total < cap) {
                    glyphs[total] = g[i];
                    faces_out[total] = runFace;
                    advances[total] = (float)adv[i].width;
                }
                total++;
            }
            free(g);
            free(adv);
        }
        CFRelease(line);
        return total;
    }
}

static CTFontRef scaledFont(int32_t face, double scale) {
    CTFontRef font = fontOf(face);
    if (font == NULL)
        return NULL;
    if (scale == 1.0)
        return font;
    if (scaled == nil)
        scaled = [NSMutableDictionary new];
    NSNumber* key = @(face);
    NSMutableDictionary<NSNumber*, id>* byScale = scaled[key];
    if (byScale == nil) {
        byScale = [NSMutableDictionary new];
        scaled[key] = byScale;
    }
    NSNumber* skey = @(scale);
    id cached = byScale[skey];
    if (cached != nil)
        return (__bridge CTFontRef)cached;
    CTFontRef made = CTFontCreateCopyWithAttributes(font, CTFontGetSize(font) * scale, NULL, NULL);
    if (made == NULL)
        return font;
    byScale[skey] = (__bridge_transfer id)made;
    return made;
}

int32_t cfont_glyph(int32_t face, uint32_t glyph, double scale,
                    int32_t* left, int32_t* top, int32_t* width, int32_t* height,
                    uint8_t* buf, int32_t cap) {
    CTFontRef font = scaledFont(face, scale);
    if (font == NULL)
        return 0;
    CGGlyph g = (CGGlyph)glyph;
    CGRect bounds = CTFontGetBoundingRectsForGlyphs(font, kCTFontOrientationHorizontal, &g, NULL, 1);
    // A pixel of slack all round: antialiasing spills past the outline.
    int32_t x0 = (int32_t)floor(CGRectGetMinX(bounds)) - 1;
    int32_t y0 = (int32_t)floor(CGRectGetMinY(bounds)) - 1;
    int32_t x1 = (int32_t)ceil(CGRectGetMaxX(bounds)) + 1;
    int32_t y1 = (int32_t)ceil(CGRectGetMaxY(bounds)) + 1;
    int32_t w = x1 - x0;
    int32_t h = y1 - y0;
    if (CGRectIsEmpty(bounds) || w <= 0 || h <= 0 || w > 4096 || h > 4096) {
        if (left) *left = 0;
        if (top) *top = 0;
        if (width) *width = 0;
        if (height) *height = 0;
        return 0;
    }
    if (left) *left = x0;
    if (top) *top = y1;
    if (width) *width = w;
    if (height) *height = h;
    int32_t need = w * h;
    if (buf == NULL || cap < need)
        return need;
    memset(buf, 0, (size_t)need);
    CGColorSpaceRef gray = CGColorSpaceCreateDeviceGray();
    CGContextRef ctx = CGBitmapContextCreate(buf, (size_t)w, (size_t)h, 8, (size_t)w, NULL, kCGImageAlphaOnly);
    CGColorSpaceRelease(gray);
    if (ctx == NULL)
        return 0;
    CGContextSetAllowsAntialiasing(ctx, true);
    CGContextSetShouldAntialias(ctx, true);
    CGContextSetAllowsFontSmoothing(ctx, false);
    CGContextSetShouldSmoothFonts(ctx, false);
    CGContextSetAllowsFontSubpixelPositioning(ctx, false);
    CGContextSetShouldSubpixelPositionFonts(ctx, false);
    CGContextSetAllowsFontSubpixelQuantization(ctx, true);
    CGContextSetShouldSubpixelQuantizeFonts(ctx, true);
    CGContextSetGrayFillColor(ctx, 1.0, 1.0);
    // The context's origin is its bottom-left; the glyph's origin goes
    // where the baseline crosses the mask's left edge.
    CGPoint origin = CGPointMake(-(CGFloat)x0, -(CGFloat)y0);
    CTFontDrawGlyphs(font, &g, &origin, 1, ctx);
    CGContextRelease(ctx);
    // Rows come out bottom first; the mask wants the top row first.
    for (int32_t y = 0; y < h / 2; y++) {
        uint8_t* a = buf + (size_t)y * (size_t)w;
        uint8_t* b = buf + (size_t)(h - 1 - y) * (size_t)w;
        for (int32_t x = 0; x < w; x++) {
            uint8_t t = a[x];
            a[x] = b[x];
            b[x] = t;
        }
    }
    return need;
}
