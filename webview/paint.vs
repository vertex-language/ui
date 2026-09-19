package webview

import cwindow

/// Pure-Vertex software rasterizer painting layout boxes into an RGBA memory buffer.
public class Painter {
    /// Renders a layout tree into a target buffer with viewport clipping and scrolling.
    public static func Paint(
        rootBox: LayoutBox,
        into buffer: inout [uint8],
        bufferWidth: int32,
        bufferHeight: int32,
        viewX: int32,
        viewY: int32,
        viewWidth: int32,
        viewHeight: int32,
        scrollX: float32,
        scrollY: float32,
        scale: float32,
        focusedNodeId: int64 = 0,
        caretIndex: int = 0
    ) {
        paintBox(
            box: rootBox,
            into: &buffer,
            bufferWidth: bufferWidth,
            bufferHeight: bufferHeight,
            viewX: viewX,
            viewY: viewY,
            viewWidth: viewWidth,
            viewHeight: viewHeight,
            scrollX: scrollX,
            scrollY: scrollY,
            scale: scale,
            focusedNodeId: focusedNodeId,
            caretIndex: caretIndex
        )
    }

    static func paintBox(
        box: LayoutBox,
        into buffer: inout [uint8],
        bufferWidth: int32,
        bufferHeight: int32,
        viewX: int32,
        viewY: int32,
        viewWidth: int32,
        viewHeight: int32,
        scrollX: float32,
        scrollY: float32,
        scale: float32,
        focusedNodeId: int64 = 0,
        caretIndex: int = 0
    ) {
        let bRect = box.BorderRect()
        let screenX = viewX + int32((bRect.x - scrollX) * scale)
        let screenY = viewY + int32((bRect.y - scrollY) * scale)
        let screenW = int32(bRect.width * scale)
        let screenH = int32(bRect.height * scale)

        // Viewport culling: skip if entirely outside viewport
        if screenY + screenH < viewY || screenY > viewY + viewHeight ||
           screenX + screenW < viewX || screenX > viewX + viewWidth {
            return
        }

        let isFocused = (box.Node != nil && box.Node?.Id == focusedNodeId)

        // 1. Draw Background
        var bgColor = box.Style.BackgroundColor
        if (box.Control == .input || box.Control == .textarea) && bgColor.A == 0 {
            bgColor = Color.white
        } else if box.Control == .button && bgColor.A == 0 {
            bgColor = Color(r: 246, g: 248, b: 250, a: 255)
        }
        if bgColor.A > 0 {
            fillRect(
                into: &buffer,
                bufferWidth: bufferWidth,
                bufferHeight: bufferHeight,
                x: screenX,
                y: screenY,
                width: screenW,
                height: screenH,
                color: bgColor,
                clipX: viewX,
                clipY: viewY,
                clipWidth: viewWidth,
                clipHeight: viewHeight
            )
        }

        // 2. Draw Borders / Focus Ring
        var bWidth = box.Style.BorderWidth
        var bColor = box.Style.BorderColor
        if (box.Control == .input || box.Control == .textarea || box.Control == .button) && bWidth == 0 {
            bWidth = 1.0
            bColor = Color(r: 208, g: 215, b: 222, a: 255)
        }
        if isFocused {
            bColor = Color(r: 9, g: 105, b: 218, a: 255)
            if bWidth < 2.0 { bWidth = 2.0 }
        }
        if bWidth > 0 && bColor.A > 0 {
            let bw = int32(bWidth * scale)
            let actualBw = bw > 0 ? bw : 1
            drawBorder(
                into: &buffer,
                bufferWidth: bufferWidth,
                bufferHeight: bufferHeight,
                x: screenX,
                y: screenY,
                width: screenW,
                height: screenH,
                borderWidth: actualBw,
                color: bColor,
                clipX: viewX,
                clipY: viewY,
                clipWidth: viewWidth,
                clipHeight: viewHeight
            )
        }

        // 2b. Draw Control Content (Input / Textarea Text & Caret)
        if box.Control == .input || box.Control == .textarea {
            let padX = int32((box.Style.PaddingLeft > 0 ? box.Style.PaddingLeft : 8.0) * scale)
            let padY = int32((box.Style.PaddingTop > 0 ? box.Style.PaddingTop : 5.0) * scale)
            let textX = screenX + padX
            let textY = screenY + padY
            let val = box.Value
            if !val.isEmpty {
                FontRenderer.DrawText(
                    into: &buffer,
                    bufferWidth: bufferWidth,
                    bufferHeight: bufferHeight,
                    x: textX,
                    y: textY,
                    text: val,
                    color: box.Style.Color,
                    fontSize: box.Style.FontSize,
                    scale: scale,
                    clipX: screenX,
                    clipY: screenY,
                    clipWidth: screenW,
                    clipHeight: screenH
                )
            } else if !box.Placeholder.isEmpty {
                FontRenderer.DrawText(
                    into: &buffer,
                    bufferWidth: bufferWidth,
                    bufferHeight: bufferHeight,
                    x: textX,
                    y: textY,
                    text: box.Placeholder,
                    color: Color(r: 140, g: 149, b: 159, a: 255),
                    fontSize: box.Style.FontSize,
                    scale: scale,
                    clipX: screenX,
                    clipY: screenY,
                    clipWidth: screenW,
                    clipHeight: screenH
                )
            }

            // Draw Caret if focused
            if isFocused {
                var caretX = textX
                if !val.isEmpty {
                    let sub = substringUpTo(val, caretIndex)
                    let m = FontRenderer.MeasureText(sub, fontSize: box.Style.FontSize)
                    caretX += int32(m.width * scale)
                }
                let caretH = int32(box.Style.FontSize * 1.1 * scale)
                fillRect(
                    into: &buffer,
                    bufferWidth: bufferWidth,
                    bufferHeight: bufferHeight,
                    x: caretX,
                    y: textY,
                    width: int32(2 * scale),
                    height: caretH > 0 ? caretH : 16,
                    color: Color.black,
                    clipX: screenX,
                    clipY: screenY,
                    clipWidth: screenW,
                    clipHeight: screenH
                )
            }
        }

        // 3. Draw Text
        if box.Kind == .text && !box.Text.isEmpty {
            let textX = viewX + int32((box.X - scrollX) * scale)
            let textY = viewY + int32((box.Y - scrollY) * scale)
            let isBold = box.Style.Bold
            let isItalic = box.Style.Italic
            FontRenderer.DrawText(
                into: &buffer,
                bufferWidth: bufferWidth,
                bufferHeight: bufferHeight,
                x: textX,
                y: textY,
                text: box.Text,
                color: box.Style.Color,
                fontSize: box.Style.FontSize,
                scale: scale,
                bold: isBold,
                italic: isItalic,
                clipX: viewX,
                clipY: viewY,
                clipWidth: viewWidth,
                clipHeight: viewHeight
            )
        }

        // 4. Draw Children recursively
        var i = 0
        while i < box.Children.count {
            paintBox(
                box: box.Children[i],
                into: &buffer,
                bufferWidth: bufferWidth,
                bufferHeight: bufferHeight,
                viewX: viewX,
                viewY: viewY,
                viewWidth: viewWidth,
                viewHeight: viewHeight,
                scrollX: scrollX,
                scrollY: scrollY,
                scale: scale,
                focusedNodeId: focusedNodeId,
                caretIndex: caretIndex
            )
            i += 1
        }
    }

    public static func fillRect(
        into buffer: inout [uint8],
        bufferWidth: int32,
        bufferHeight: int32,
        x: int32,
        y: int32,
        width: int32,
        height: int32,
        color: Color,
        clipX: int32,
        clipY: int32,
        clipWidth: int32,
        clipHeight: int32
    ) {
        if color.A == 0 || width <= 0 || height <= 0 { return }

        buffer.withUnsafeMutableBufferPointer { bp in
            if let addr = bp.baseAddress {
                cwindow_fill_rect(
                    addr,
                    bufferWidth,
                    bufferHeight,
                    x,
                    y,
                    width,
                    height,
                    color.R,
                    color.G,
                    color.B,
                    color.A,
                    clipX,
                    clipY,
                    clipWidth,
                    clipHeight
                )
            }
        }
    }

    static func drawBorder(
        into buffer: inout [uint8],
        bufferWidth: int32,
        bufferHeight: int32,
        x: int32,
        y: int32,
        width: int32,
        height: int32,
        borderWidth: int32,
        color: Color,
        clipX: int32,
        clipY: int32,
        clipWidth: int32,
        clipHeight: int32
    ) {
        // Top edge
        fillRect(into: &buffer, bufferWidth: bufferWidth, bufferHeight: bufferHeight, x: x, y: y, width: width, height: borderWidth, color: color, clipX: clipX, clipY: clipY, clipWidth: clipWidth, clipHeight: clipHeight)
        // Bottom edge
        fillRect(into: &buffer, bufferWidth: bufferWidth, bufferHeight: bufferHeight, x: x, y: y + height - borderWidth, width: width, height: borderWidth, color: color, clipX: clipX, clipY: clipY, clipWidth: clipWidth, clipHeight: clipHeight)
        // Left edge
        fillRect(into: &buffer, bufferWidth: bufferWidth, bufferHeight: bufferHeight, x: x, y: y, width: borderWidth, height: height, color: color, clipX: clipX, clipY: clipY, clipWidth: clipWidth, clipHeight: clipHeight)
        // Right edge
        fillRect(into: &buffer, bufferWidth: bufferWidth, bufferHeight: bufferHeight, x: x + width - borderWidth, y: y, width: borderWidth, height: height, color: color, clipX: clipX, clipY: clipY, clipWidth: clipWidth, clipHeight: clipHeight)
    }

    static func min(_ a: int32, _ b: int32) -> int32 { return a < b ? a : b }
    static func max(_ a: int32, _ b: int32) -> int32 { return a > b ? a : b }
}
