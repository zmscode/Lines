// Renders the app icon: a Bézier curve with its anchor points and handles,
// on a squircle following the macOS icon grid (824pt artwork in a 1024pt canvas).
import AppKit

let out = CommandLine.arguments[1]
let sizes = [16, 32, 128, 256, 512]
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)

func render(_ px: Int) -> Data {
	let rep = NSBitmapImageRep(
		bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
		samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
		bytesPerRow: 0, bitsPerPixel: 0)!
	NSGraphicsContext.saveGraphicsState()
	let ctx = NSGraphicsContext(bitmapImageRep: rep)!
	NSGraphicsContext.current = ctx
	let s = CGFloat(px) / 1024
	ctx.cgContext.scaleBy(x: s, y: s)

	let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
	let shape = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)

	NSGraphicsContext.saveGraphicsState()
	let shadow = NSShadow()
	shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
	shadow.shadowBlurRadius = 20
	shadow.shadowOffset = NSSize(width: 0, height: -10)
	shadow.set()
	NSColor.white.setFill()
	shape.fill()
	NSGraphicsContext.restoreGraphicsState()

	NSGradient(colors: [
		NSColor(srgbRed: 0.98, green: 0.98, blue: 1, alpha: 1),
		NSColor(srgbRed: 0.88, green: 0.90, blue: 0.95, alpha: 1),
	])!
	.draw(in: shape, angle: -90)

	// Faint grid
	NSGraphicsContext.saveGraphicsState()
	shape.addClip()
	NSColor(srgbRed: 0.2, green: 0.3, blue: 0.5, alpha: 0.07).setStroke()
	for i in stride(from: 100, through: 924, by: 82) {
		let g = NSBezierPath()
		g.lineWidth = 3
		g.move(to: NSPoint(x: CGFloat(i), y: 100))
		g.line(to: NSPoint(x: CGFloat(i), y: 924))
		g.move(to: NSPoint(x: 100, y: CGFloat(i)))
		g.line(to: NSPoint(x: 924, y: CGFloat(i)))
		g.stroke()
	}
	NSGraphicsContext.restoreGraphicsState()

	let a = NSPoint(x: 250, y: 330)
	let b = NSPoint(x: 774, y: 694)
	let c1 = NSPoint(x: 330, y: 760)
	let c2 = NSPoint(x: 694, y: 260)
	let accent = NSColor(srgbRed: 0.04, green: 0.45, blue: 1, alpha: 1)

	// Handles
	let handles = NSBezierPath()
	handles.lineWidth = 10
	handles.move(to: a)
	handles.line(to: c1)
	handles.move(to: b)
	handles.line(to: c2)
	NSColor(srgbRed: 0.45, green: 0.5, blue: 0.6, alpha: 1).setStroke()
	handles.stroke()

	// Curve
	let curve = NSBezierPath()
	curve.lineWidth = 44
	curve.lineCapStyle = .round
	curve.move(to: a)
	curve.curve(to: b, controlPoint1: c1, controlPoint2: c2)
	NSGradient(colors: [
		NSColor(srgbRed: 0.35, green: 0.3, blue: 1, alpha: 1), accent,
		NSColor(srgbRed: 0.1, green: 0.75, blue: 0.95, alpha: 1),
	])!
	.draw(
		in: NSBezierPath(
			cgPath: curve.cgPath.copy(
				strokingWithWidth: 44, lineCap: .round, lineJoin: .round, miterLimit: 10)), angle: 0
	)

	// Control points (circles) and anchors (squares)
	for p in [c1, c2] {
		let r = NSRect(x: p.x - 26, y: p.y - 26, width: 52, height: 52)
		let o = NSBezierPath(ovalIn: r)
		NSColor.white.setFill()
		o.fill()
		o.lineWidth = 10
		NSColor(srgbRed: 0.45, green: 0.5, blue: 0.6, alpha: 1).setStroke()
		o.stroke()
	}
	for p in [a, b] {
		let r = NSRect(x: p.x - 34, y: p.y - 34, width: 68, height: 68)
		let q = NSBezierPath(roundedRect: r, xRadius: 10, yRadius: 10)
		NSColor.white.setFill()
		q.fill()
		q.lineWidth = 12
		accent.setStroke()
		q.stroke()
	}

	NSGraphicsContext.restoreGraphicsState()
	return rep.representation(using: .png, properties: [:])!
}

for size in sizes {
	try! render(size).write(to: URL(fileURLWithPath: "\(out)/icon_\(size)x\(size).png"))
	try! render(size * 2).write(to: URL(fileURLWithPath: "\(out)/icon_\(size)x\(size)@2x.png"))
}
