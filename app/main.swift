// Dusk Wallpaper: a live calendar wallpaper drawn behind the desktop icons.
//
// One file. AppKit + Core Animation + Core Text only: no web view, no helper processes, and no work at all while
// nothing changes or nobody can see it. The gradient is a small 16-bit Display P3 bitmap that Core Animation stretches
// over the screen; the type is two small alpha masks tinted with the palette's ink. Auto flows from one gradient to the
// next in steps too small to see: round the light palettes by day and through shades of Night after dark, following
// the Mac's Light and Dark appearance. It behaves as a wallpaper does: it starts with the Mac and stays up when the app
// is quit, until it is turned off. Build and install with ./build.sh.
//
// Headless (no window; for checks and exports):
//   DuskWallpaper --render out.png [--size 1800x1169] [--scale 2] [--date 2026-11-11] [--no-strip] [--no-info] [--no-text]
//                 [--palette dusk | --at 1.5 [--dark] | --custom "r,g,b;r,g,b;r,g,b" | --p3 "r,g,b;r,g,b;..."]
//       --at takes a point on Auto's path (one unit is one gradient; --dark for the path it takes at night).
//       --custom takes the three colours of the settings window, --p3 a whole palette; both as Display P3, 0...1:
//       bottom-left; top-right; lower-right and then, for --p3, upper-left; base; ink.
//   DuskWallpaper --render-settings out.png      the settings window, drawn off screen

import AppKit
import ServiceManagement
import UniformTypeIdentifiers

// MARK: - Colour and palettes

/// A colour as gamma-encoded Display P3 components, 0...1. A Display P3 screen shows them as they are.
struct RGB: Equatable, Codable {
    var r, g, b: Double
    init(_ r: Double, _ g: Double, _ b: Double) { self.r = r; self.g = g; self.b = b }
    func mix(_ o: RGB, _ t: Double) -> RGB { RGB(r + (o.r - r) * t, g + (o.g - g) * t, b + (o.b - b) * t) }
    func cg(_ alpha: CGFloat = 1) -> CGColor { CGColor(colorSpace: Palette.space, components: [CGFloat(r), CGFloat(g), CGFloat(b), alpha]) ?? .black }
    private var linear: [Double] { [r, g, b].map { $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) } }
    /// Relative luminance (Display P3 weights on linear light), for contrast decisions.
    var luminance: Double { let v = linear; return 0.229 * v[0] + 0.692 * v[1] + 0.079 * v[2] }
    func contrast(_ o: RGB) -> Double { (max(luminance, o.luminance) + 0.05) / (min(luminance, o.luminance) + 0.05) }

    // OKLCH (lightness, chroma, hue): a blend made there keeps its colour, where a plain mix of two hues passes through grey.
    // The two matrices take linear Display P3 to and from the cone space OKLab is built on (CSS Color 4 values).
    private static let toLMS = [[0.4813798527, 0.4621183710, 0.0565017762], [0.2288319418, 0.6532168194, 0.1179512388], [0.0839457523, 0.2241652710, 0.6918889767]]
    private static let fromLMS = [[3.1277689714, -2.2571357626, 0.1293667912], [-1.0910090184, 2.4133317103, -0.3223226919], [-0.0260108019, -0.5080413317, 1.5340521336]]
    private var lch: (l: Double, c: Double, h: Double) {
        let v = linear, m = RGB.toLMS.map { cbrt($0[0] * v[0] + $0[1] * v[1] + $0[2] * v[2]) }
        let a = 1.9779985324 * m[0] - 2.4285922420 * m[1] + 0.4505937096 * m[2], b = 0.0259040425 * m[0] + 0.7827717125 * m[1] - 0.8086757549 * m[2]
        return (0.2104542683 * m[0] + 0.7936177747 * m[1] - 0.0040720430 * m[2], (a * a + b * b).squareRoot(), atan2(b, a))
    }
    private init(l: Double, c: Double, h: Double) {
        func light(_ chroma: Double) -> [Double] {                             // linear Display P3 for this lightness and hue at a given chroma
            let a = chroma * cos(h), b = chroma * sin(h)
            let m = [l + 0.3963377774 * a + 0.2158037573 * b, l - 0.1055613458 * a - 0.0638541728 * b, l - 0.0894841775 * a - 1.2914855480 * b].map { $0 * $0 * $0 }
            return RGB.fromLMS.map { $0[0] * m[0] + $0[1] * m[1] + $0[2] * m[2] }
        }
        func fits(_ chroma: Double) -> Bool { light(chroma / 0.94).allSatisfy { $0 > -0.0005 && $0 < 1.0005 } }     // with a little room to spare, like the tuned palettes
        var chroma = c
        if !fits(chroma) {                                                     // more vivid than the panel shows comfortably: ease the chroma back until it fits
            var outside = c
            chroma = 0
            for _ in 0..<12 { let mid = (chroma + outside) / 2; if fits(mid) { chroma = mid } else { outside = mid } }
        }
        let v = light(chroma)
        let e = v.map { x -> Double in let x = min(1, max(0, x)); return x <= 0.0031308 ? 12.92 * x : 1.055 * pow(x, 1 / 2.4) - 0.055 }
        self.init(e[0], e[1], e[2])
    }
    /// A blend that travels round the hue circle the short way, so two colours meet in colour and not in grey.
    func flow(to o: RGB, _ t: Double) -> RGB {
        let a = lch, b = o.lch
        var turn = b.h - a.h
        if turn > .pi { turn -= 2 * .pi } else if turn < -.pi { turn += 2 * .pi }
        let h = a.c < 0.02 ? b.h : b.c < 0.02 ? a.h : a.h + turn * t           // a near-grey has no hue of its own
        return RGB(l: a.l + (b.l - a.l) * t, c: a.c + (b.c - a.c) * t, h: h)
    }
    /// The same colour with its hue moved round the colour wheel.
    func turned(_ degrees: Double) -> RGB { let v = lch; return RGB(l: v.l, c: v.c, h: v.h + degrees * .pi / 180) }
}

struct Palette: Equatable {
    var c: [RGB]            // the four blobs: bottom-left, top-right, lower-right, upper-left
    var base, ink: RGB      // the colour behind the blobs, and the colour of all type
    static let space = CGColorSpace(name: CGColorSpace.displayP3) ?? CGColorSpaceCreateDeviceRGB()

    init(_ v: [RGB]) { c = Array(v[0..<4]); base = v[4]; ink = v[5] }
    /// Three picked colours become a whole palette; the type takes whichever ink reads better on it.
    init(custom a: [RGB]) {
        let white = RGB(1, 1, 1), dark = Presets.palette("dusk").ink, light = Presets.palette("night").ink
        c = [a[0], a[1], a[2], a[0].mix(white, 0.7)]
        base = a[0].mix(a[1], 0.5).mix(a[2], 0.33).mix(white, 0.6)
        let behindType = [c[0], c[2], base]
        func worst(_ ink: RGB) -> Double { behindType.map(ink.contrast).min() ?? 1 }
        ink = worst(light) > worst(dark) ? light : dark
    }
    var isDark: Bool { ink.luminance > 0.5 }
    func mix(_ o: Palette, _ t: Double) -> Palette {
        var p = self
        p.c = zip(c, o.c).map { $0.mix($1, t) }; p.base = base.mix(o.base, t); p.ink = ink.mix(o.ink, t)
        return p
    }
    /// The picture part of the way from this palette to another, every colour taking the colourful route.
    func flow(to o: Palette, _ t: Double) -> Palette {
        var p = self
        p.c = zip(c, o.c).map { $0.flow(to: $1, t) }; p.base = base.flow(to: o.base, t); p.ink = ink.mix(o.ink, t)
        return p
    }
    /// The same picture with every hue moved round the colour wheel; lightness, strength and ink stay as they are.
    func turned(_ degrees: Double) -> Palette {
        var p = self
        p.c = c.map { $0.turned(degrees) }; p.base = base.turned(degrees)
        return p
    }
}

enum Presets {
    /// In the order Auto walks them, which is also the order the settings show: neighbours are always clearly different.
    static let ring = ["dusk", "meadow", "ember", "ocean", "dawn", "night"]
    /// Tuned for a wide-colour (Display P3) panel: some of these colours do not exist in sRGB.
    static let all: [String: Palette] = [
        "dusk": Palette([RGB(0.9831, 0.7218, 0.5130), RGB(0.6705, 0.5629, 0.9331), RGB(0.9639, 0.6874, 0.7441), RGB(0.9834, 0.9097, 0.8339), RGB(0.9501, 0.8344, 0.8161), RGB(0.1209, 0.0728, 0.1291)]),
        "dawn": Palette([RGB(0.9825, 0.8572, 0.5906), RGB(0.9508, 0.6887, 0.7603), RGB(0.9776, 0.7793, 0.7833), RGB(0.9764, 0.9556, 0.8346), RGB(0.9720, 0.8951, 0.7973), RGB(0.1427, 0.0803, 0.0551)]),
        "ocean": Palette([RGB(0.5550, 0.9058, 0.9047), RGB(0.3036, 0.5412, 0.9239), RGB(0.5283, 0.7850, 0.9397), RGB(0.8451, 0.9787, 0.9568), RGB(0.7305, 0.8872, 0.9348), RGB(0.0406, 0.1043, 0.1696)]),
        "meadow": Palette([RGB(0.7427, 0.9217, 0.5842), RGB(0.4021, 0.7929, 0.5598), RGB(0.9801, 0.9451, 0.7042), RGB(0.9673, 0.9691, 0.8278), RGB(0.8675, 0.9343, 0.7877), RGB(0.0544, 0.1187, 0.0715)]),
        "ember": Palette([RGB(0.9697, 0.5880, 0.3788), RGB(0.8821, 0.4192, 0.4198), RGB(0.9732, 0.8245, 0.5190), RGB(0.9819, 0.9298, 0.7878), RGB(0.9303, 0.8085, 0.6825), RGB(0.1403, 0.0550, 0.0522)]),
        "night": Palette([RGB(0.2399, 0.1433, 0.5797), RGB(0.0543, 0.2841, 0.6036), RGB(0.4509, 0.1313, 0.3713), RGB(0.1008, 0.1210, 0.2760), RGB(0.0465, 0.0475, 0.1092), RGB(0.9437, 0.9354, 0.9666)]),
    ]
    static func palette(_ name: String) -> Palette { all[name] ?? all["dusk"]! }

    /// What Auto moves through. By day: round the light palettes. After dark: Night, its hues swinging a sixth of the way
    /// round the colour wheel and back (towards teal and blue one way, towards wine and amber the other).
    static let day = ring.filter { !palette($0).isDark }
    /// The two day palettes a position on that path lies between, and how far it is from the first to the second.
    static func leg(at position: Double) -> (from: String, to: String, t: Double) {
        let n = Double(day.count), q = position - n * floor(position / n), i = min(day.count - 1, Int(q))
        return (day[i], day[(i + 1) % day.count], q - Double(i))
    }
    /// The picture at a position on the path; one unit is one gradient.
    static func picture(at position: Double, dark: Bool) -> Palette {
        if dark {
            let q = position - 4 * floor(position / 4)
            return palette("night").turned(q < 2 ? 60 * (q - 1) : 60 * (3 - q))
        }
        let leg = leg(at: position)
        return palette(leg.from).flow(to: palette(leg.to), leg.t)
    }
    /// The preset nearest to that position, for the settings window to point at.
    static func name(at position: Double, dark: Bool) -> String { dark ? "night" : leg(at: position + 0.5).from }
}

// MARK: - Settings

struct Settings: Codable {
    enum Mode: String, Codable { case auto, preset, custom }                // flowing by itself, one of the presets, or the owner's own colours
    static let paces: [TimeInterval] = [10, 20, 30, 60, 300]                // seconds Auto can take from one gradient to the next
    var mode = Mode.auto
    var preset = "dusk"
    var custom = Array(Presets.palette("dusk").c[0..<3])
    var strip = true, info = true, startAtLogin = true
    // Auto: what is on screen is a pure function of the clock and these three values, so nothing can drift.
    var pace: TimeInterval = 20
    var autoStart = Date(timeIntervalSinceReferenceDate: 0)
    var autoBase = 0.0                          // where on its path Auto was at autoStart; one unit is one gradient

    init() {}
    init(from decoder: any Decoder) throws {    // every key is optional, so adding a setting later never resets the others
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func saved<T: Decodable>(_ key: CodingKeys, or value: T) -> T { (try? c.decode(T.self, forKey: key)) ?? value }
        mode = saved(.mode, or: mode); preset = saved(.preset, or: preset); custom = saved(.custom, or: custom)
        strip = saved(.strip, or: strip); info = saved(.info, or: info); startAtLogin = saved(.startAtLogin, or: startAtLogin)
        pace = saved(.pace, or: pace); autoStart = saved(.autoStart, or: autoStart); autoBase = saved(.autoBase, or: autoBase)
    }

    static func load() -> Settings {
        var s = UserDefaults.standard.data(forKey: "settings").flatMap { try? JSONDecoder().decode(Settings.self, from: $0) } ?? Settings()
        let pace = s.pace
        if Presets.all[s.preset] == nil { s.preset = "dusk" }
        if s.custom.count != 3 { s.custom = Settings().custom }
        s.pace = paces.min { abs($0 - pace) < abs($1 - pace) } ?? 20
        if !s.autoBase.isFinite { s.autoBase = 0 }
        return s
    }
    func save() { if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(data, forKey: "settings") } }

    /// Where Auto is on its path at `now`.
    func position(at now: Date) -> Double { autoBase + now.timeIntervalSince(autoStart) / pace }
    /// What Auto shows at `now`: the two key pictures the screen is between, how far between them, and when the next small
    /// step is due. Twelve key pictures per gradient follow the colourful route; between two of them the graphics chip
    /// blends, in steps too small to see and at most twenty a second.
    func flow(at now: Date, dark: Bool) -> (a: Palette, b: Palette, f: Double, next: Date) {
        let keys = 12.0, fine = max(1, min(20, floor(pace / keys / 0.05))), grain = keys * fine
        // A millisecond of allowance: a timer that fires on a step, or a hair early, has reached it and so never fires for it twice.
        let steps = floor(position(at: now.addingTimeInterval(0.001)) * grain), key = floor(steps / fine)
        return (Presets.picture(at: key / keys, dark: dark), Presets.picture(at: (key + 1) / keys, dark: dark), (steps - key * fine) / fine,
                autoStart.addingTimeInterval((steps + 1 - autoBase * grain) / grain * pace))
    }
    /// The preset on screen at `now` (while Auto runs, the nearest one), or nil while the owner's own colours show.
    func shownName(at now: Date, dark: Bool) -> String? {
        switch mode { case .auto: Presets.name(at: position(at: now), dark: dark); case .preset: preset; case .custom: nil }
    }
    func palette(at now: Date, dark: Bool) -> Palette {
        switch mode { case .auto: Presets.picture(at: position(at: now), dark: dark); case .preset: Presets.palette(preset); case .custom: Palette(custom: custom) }
    }
}

// MARK: - The gradient

enum Picture {
    /// One soft ellipse: centre as a fraction of the canvas (y from the top), radii in units of max(width, height); it has faded out at `stop` x radius.
    struct Blob { let cx, cy, rx, ry, stop: Float }
    static let blobs = [Blob(cx: 0.08, cy: 1.00, rx: 0.90, ry: 0.70, stop: 0.58), Blob(cx: 0.96, cy: 0.00, rx: 0.80, ry: 0.80, stop: 0.60),
                        Blob(cx: 0.70, cy: 0.78, rx: 0.50, ry: 0.40, stop: 0.70), Blob(cx: 0.30, cy: 0.20, rx: 0.50, ry: 0.50, stop: 0.70)]

    /// The gradient as an opaque 16-bit image tagged Display P3. It must be deep: Core Animation dithers a 16-bit source
    /// by itself when it puts it on screen, while an 8-bit one would show bands.
    static func gradient(_ p: Palette, canvas: CGSize, width w: Int, height h: Int) -> CGImage? {
        let W = Float(canvas.width), H = Float(canvas.height), vmax = max(W, H)
        let layers = [3, 2, 1, 0].map { i -> (cx: Float, cy: Float, ix: Float, iy: Float, r: Float, g: Float, b: Float) in    // painted bottom to top
            let s = blobs[i], c = p.c[i]
            return (s.cx * W, s.cy * H, 1 / (s.rx * s.stop * vmax), 1 / (s.ry * s.stop * vmax), Float(c.r), Float(c.g), Float(c.b))
        }
        // The pixels get pages of their own, handed back to the system the moment the image is let go. Pictures come and go
        // all the time while Auto flows, and ordinary allocations of this size would linger as used memory.
        let size = w * h * 8, pages = (size + 16383) & ~16383
        guard w > 0, h > 0, let memory = mmap(nil, pages, PROT_READ | PROT_WRITE, MAP_ANON | MAP_PRIVATE, -1, 0), memory != MAP_FAILED,
              let provider = CGDataProvider(dataInfo: UnsafeMutableRawPointer(bitPattern: pages), data: memory, size: size,
                                            releaseData: { info, data, _ in munmap(UnsafeMutableRawPointer(mutating: data), Int(bitPattern: info)) }) else { return nil }
        let px = memory.assumingMemoryBound(to: UInt16.self), base = (r: Float(p.base.r), g: Float(p.base.g), b: Float(p.base.b))
        // Each blob's squared distance across is worked out once per column, and down once per row: a pixel then costs
        // an addition and a comparison per blob, and a square root only where it lies inside one.
        let across = layers.flatMap { s in (0..<w).map { x -> Float in let dx = ((Float(x) + 0.5) / Float(w) * W - s.cx) * s.ix; return dx * dx } }
        var down = [Float](repeating: 0, count: layers.count)
        for y in 0..<h {                                                       // row 0 is the top of the picture
            let fy = (Float(y) + 0.5) / Float(h) * H
            for (k, s) in layers.enumerated() { let dy = (fy - s.cy) * s.iy; down[k] = dy * dy }
            for x in 0..<w {
                var r = base.r, g = base.g, b = base.b
                for (k, s) in layers.enumerated() {
                    let d2 = across[k * w + x] + down[k]
                    if d2 < 1 {
                        let t = 1 - d2.squareRoot(), a = t * t * (3 - 2 * t)   // smooth falloff: no cone tip at the centre, no ring at the rim
                        r += (s.r - r) * a; g += (s.g - g) * a; b += (s.b - b) * a
                    }
                }
                let i = (y * w + x) * 4
                px[i] = UInt16(max(0, min(65535, r * 65535 + 0.5))); px[i + 1] = UInt16(max(0, min(65535, g * 65535 + 0.5)))
                px[i + 2] = UInt16(max(0, min(65535, b * 65535 + 0.5))); px[i + 3] = 65535
            }
        }
        return CGImage(width: w, height: h, bitsPerComponent: 16, bitsPerPixel: 64, bytesPerRow: w * 8, space: Palette.space,
                       bitmapInfo: CGBitmapInfo(alpha: .noneSkipLast, byteOrder: .order16Little), provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    /// The whole wallpaper as a 16-bit PNG with an embedded Display P3 profile, at any size: the same gradient function
    /// evaluated for every output pixel, and the same type.
    static func writePNG(to url: URL, palette p: Palette, canvas: CGSize, scale: CGFloat, date: Date, strip: Bool, info: Bool, text: Bool) -> Bool {
        let w = Int((canvas.width * scale).rounded()), h = Int((canvas.height * scale).rounded())
        guard let image = gradient(p, canvas: canvas, width: w, height: h),
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 16, bytesPerRow: 0, space: Palette.space, bitmapInfo: image.bitmapInfo) else { return false }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        if text {
            ctx.scaleBy(x: scale, y: scale)
            let marks = Lettering.layout(canvas: canvas, date: date, strip: strip, info: info)
            Lettering.draw(marks.block + marks.strip, in: ctx, canvasHeight: canvas.height, ink: p.ink)
        }
        guard let out = ctx.makeImage(), let file = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return false }
        CGImageDestinationAddImage(file, out, nil)
        return CGImageDestinationFinalize(file)
    }
}

// MARK: - The type

/// One thing to draw: a line of text (x, baseline) or, when `line` is nil, a dot (x, top edge, diameter). y is measured from the top of the canvas.
struct Mark { var line: CTLine?; var x, y, size, alpha: CGFloat }

enum Lettering {
    /// The system font at an exact weight (the `wght` axis value, as CSS font-weight does) with fixed-width digits.
    static func font(_ size: CGFloat, _ weight: CGFloat) -> CTFont {
        let d = NSFont.systemFont(ofSize: size).fontDescriptor.addingAttributes([
            .variation: [NSNumber(value: 0x77676874 as UInt32): weight],
            .featureSettings: [[NSFontDescriptor.FeatureKey.typeIdentifier: kNumberSpacingType, NSFontDescriptor.FeatureKey.selectorIdentifier: kMonospacedNumbersSelector]]])
        return (NSFont(descriptor: d, size: size) ?? .systemFont(ofSize: size)) as CTFont
    }
    static func line(_ s: String, _ f: CTFont, kern: CGFloat = 0) -> (CTLine, CGFloat) {
        var a: [NSAttributedString.Key: Any] = [.font: f, NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true]
        if kern != 0 { a[.kern] = kern }                                       // a kern of 0 would switch off the font's own kerning
        let l = CTLineCreateWithAttributedString(NSAttributedString(string: s, attributes: a))
        return (l, CGFloat(CTLineGetTypographicBounds(l, nil, nil, nil)))
    }

    /// Everything that is written on the wallpaper for `date`, as marks in canvas points: a small date block lower left
    /// and one line of the month's days.
    ///
    /// The numbers are the stylesheet of the web page this look was first drawn on: vw and vh are hundredths of
    /// the canvas, sizes and gaps are that page's values, and strut, box and rise reproduce how a browser places a line of text.
    /// On an upright (rotated) display vh follows the width instead, so the type keeps its proportions.
    static func layout(canvas: CGSize, date: Date, strip showStrip: Bool, info showInfo: Bool) -> (block: [Mark], strip: [Mark]) {
        let W = canvas.width, H = canvas.height, vw = W / 100, vh = min(H, 0.65 * W) / 100
        var cal = Calendar(identifier: .gregorian)
        cal.locale = .current; cal.timeZone = .current
        let c = cal.dateComponents([.year, .month, .day, .weekday], from: date)
        let day = c.day ?? 1, month = c.month ?? 1, year = c.year ?? 2000, today = cal.startOfDay(for: date)
        var iso = Calendar(identifier: .iso8601); iso.timeZone = .current
        let lastDay = cal.date(from: DateComponents(year: year, month: 12, day: 31)) ?? today
        let left = cal.dateComponents([.day], from: today, to: lastDay).day ?? 0
        let weekday = cal.weekdaySymbols[(c.weekday ?? 1) - 1].uppercased(), monthName = cal.monthSymbols[month - 1]
        let infoLeft = "WEEK \(iso.component(.weekOfYear, from: date))", infoRight = "\(left) \(left == 1 ? "DAY" : "DAYS") LEFT IN \(year)"

        func size(_ f: CTFont) -> CGFloat { CTFontGetSize(f) }
        func box(_ f: CTFont) -> CGFloat { CTFontGetAscent(f).rounded() + CTFontGetDescent(f).rounded() }                    // height of one line
        func rise(_ f: CTFont) -> CGFloat { (box(f) - CTFontGetAscent(f) - CTFontGetDescent(f)) / 2 + CTFontGetAscent(f) }   // baseline, measured down from the top of its line
        func mid(_ f: CTFont) -> CGFloat { (CTFontGetAscent(f) - CTFontGetDescent(f)) / 2 }
        func text(_ l: CTLine, _ x: CGFloat, _ y: CGFloat, _ alpha: CGFloat) -> Mark { Mark(line: l, x: x, y: y, size: 0, alpha: alpha) }
        func dot(_ x: CGFloat, _ y: CGFloat, _ d: CGFloat, _ alpha: CGFloat) -> Mark { Mark(line: nil, x: x, y: y, size: d, alpha: alpha) }
        let strut = font(16, 400), strutUp = rise(strut), strutDown = box(strut) - strutUp
        var block: [Mark] = [], strip: [Mark] = []

        let bottom = H - 23 * vh                                           // the block sits on this line and grows upward
        let fNum = font(17 * vh, 200), fDow = font(0.72 * vw, 400), fMon = font(1.2 * vw, 400), fInfo = font(0.62 * vw, 500)
        let (lNum, wNum) = line(String(day), fNum, kern: -0.04 * size(fNum))
        block.append(text(lNum, 6 * vw - 0.05 * size(fNum), bottom - 0.39 * size(fNum) + mid(fNum), 0.88))
        let x = 6 * vw + wNum - 0.05 * size(fNum) + 1.5 * vw               // the three lines beside the numeral
        var rowTop = bottom
        if showInfo {
            let base = bottom - strutDown, top = base - rise(fInfo), gap = size(fInfo)
            let (l1, w1) = line(infoLeft, fInfo, kern: 0.14 * gap), (l2, _) = line(infoRight, fInfo, kern: 0.14 * gap)
            block += [text(l1, x, base, 0.55), dot(x + w1 + gap, top + (box(fInfo) - 3) / 2, 3, 0.4), text(l2, x + w1 + gap + 3 + gap, base, 0.55)]
            rowTop = top - 0.9 * vh
        }
        let monTop = rowTop - box(fMon)
        let (lMon, wMon) = line(monthName, fMon, kern: -0.01 * size(fMon)), (lYear, _) = line(String(year), fMon, kern: -0.01 * size(fMon))
        block += [text(lMon, x, monTop + rise(fMon), 1), text(lYear, x + wMon + 0.45 * size(fMon), monTop + rise(fMon), 0.45)]
        let dowTop = monTop - 0.7 * vh - box(fDow)
        block.append(text(line(weekday, fDow, kern: 0.34 * size(fDow)).0, x, dowTop + rise(fDow), 0.55))

        if showStrip {                                                     // every day of the month on one line
            let days = cal.range(of: .day, in: .month, for: date)?.count ?? 30
            let inset = 5.6 * vw, cell = 1.6 * vw, f = font(0.8 * vw, 400), fToday = font(0.8 * vw, 700)
            let top = H - 15 * vh - box(f), pitch = (W - 2 * inset - cell) / CGFloat(max(1, days - 1))
            for d in 1...days {
                let cx = inset + cell / 2 + pitch * CGFloat(d - 1)
                let wd = cal.component(.weekday, from: cal.date(from: DateComponents(year: year, month: month, day: d)) ?? date)
                let (l, w) = line(String(d), d == day ? fToday : f)
                strip.append(text(l, cx - w / 2, top + rise(f), d == day ? 1 : d < day ? 0.28 : (wd == 1 || wd == 7) ? 0.34 : 0.62))    // gone by, weekend, to come
                if d == day { strip.append(dot(cx - 0.16 * vw, top - 1.1 * vh, 0.32 * vw, 1)) }
            }
        }
        return (block, strip)
    }

    /// Draws marks into a context whose units are canvas points with the origin at the bottom left.
    static func draw(_ marks: [Mark], in ctx: CGContext, canvasHeight H: CGFloat, ink: RGB) {
        ctx.setAllowsFontSmoothing(false); ctx.setShouldSmoothFonts(false)     // smoothing would thicken the type, most of all light type on dark
        ctx.setAllowsFontSubpixelPositioning(true); ctx.setShouldSubpixelPositionFonts(true)
        ctx.setAllowsFontSubpixelQuantization(false); ctx.setShouldSubpixelQuantizeFonts(false)
        for m in marks {
            ctx.setFillColor(ink.cg(m.alpha))
            if let l = m.line { ctx.textPosition = CGPoint(x: m.x, y: H - m.y); CTLineDraw(l, ctx) }
            else { ctx.fillEllipse(in: CGRect(x: m.x, y: H - m.y - m.size, width: m.size, height: m.size)) }
        }
    }
    /// The smallest rectangle (bottom-left origin) that holds the marks, glyph outlines included, so a text layer never needs a screen-sized backing store.
    static func bounds(_ marks: [Mark], canvasHeight H: CGFloat) -> CGRect {
        marks.reduce(CGRect.null) { r, m in
            guard let l = m.line else { return r.union(CGRect(x: m.x, y: H - m.y - m.size, width: m.size, height: m.size)) }
            return r.union(CTLineGetBoundsWithOptions(l, []).union(CTLineGetBoundsWithOptions(l, .useGlyphPathBounds)).offsetBy(dx: m.x, dy: H - m.y))
        }
    }
}

/// The type as an alpha mask. The layer it masks is a flat fill of the ink colour, so changing the ink redraws nothing.
final class TextMask: CALayer {
    var marks: [Mark] = [], origin = CGPoint.zero, canvasHeight: CGFloat = 0
    override func draw(in ctx: CGContext) {
        ctx.translateBy(x: -origin.x, y: -origin.y)
        Lettering.draw(marks, in: ctx, canvasHeight: canvasHeight, ink: RGB(0, 0, 0))
    }
}

// MARK: - One wallpaper window per display

@MainActor final class Wall {
    let window: NSWindow
    private(set) var shown: Palette
    private let root = CALayer(), old = CALayer(), gradient = CALayer()
    private let type = [CALayer(), CALayer()], masks = [TextMask(), TextMask()]         // the date block and the day line
    private var fade: (from: Palette, oldOnTop: Bool)?                                  // while a fade runs: the picture in `old`, and which layer is fading
    private var flowKeys: (a: Palette, b: Palette)?                                     // while flowing: the two key pictures loaded in `old` and `gradient`
    private var generation = 0, size = CGSize.zero, scale: CGFloat = 0, textKey = ""
    private var pixels: (w: Int, h: Int) {                                              // 450 x 292 on a 14-inch MacBook Pro: finer gains nothing once stretched
        let k = 450 / max(size.width, size.height, 1)
        return (max(64, Int(size.width * k)), max(64, Int(size.height * k)))
    }
    private static let slowRate = CAFrameRateRange(minimum: 15, maximum: 30, preferred: 30)    // a slow dissolve gains nothing from 120 Hz
    var isVisible: Bool { window.occlusionState.contains(.visible) }

    init(screen: NSScreen, palette: Palette) {
        shown = palette
        window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)     // above the system wallpaper, below the desktop icons
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.hasShadow = false
        window.canHide = false
        window.isRestorable = false
        window.isExcludedFromWindowsMenu = true
        window.animationBehavior = .none
        window.backgroundColor = NSColor(cgColor: palette.base.cg()) ?? .black
        let view = NSView(frame: CGRect(origin: .zero, size: screen.frame.size))
        view.layer = root                                                      // we own the layer tree: nothing here ever gets a screen-sized drawn backing store
        view.wantsLayer = true
        window.contentView = view
        root.isOpaque = true
        let still: [String: any CAAction] = ["contents": NSNull(), "bounds": NSNull(), "position": NSNull(), "hidden": NSNull(), "opacity": NSNull(), "zPosition": NSNull(), "backgroundColor": NSNull()]
        for layer in [old, gradient] { layer.isOpaque = true; layer.contentsGravity = .resize }
        for (tint, mask) in zip(type, masks) {
            mask.contentsFormat = .gray8Uint; mask.actions = still
            tint.mask = mask
            tint.backgroundColor = palette.ink.cg()
        }
        for layer in [old, gradient] + type {                                  // back to front; nothing animates unless show() says so
            layer.actions = still
            root.addSublayer(layer)
        }
        fit(screen)
        window.orderFront(nil)
    }

    /// Follows the display's frame and scale. Does nothing when neither changed, which is what most screen notifications are.
    func fit(_ screen: NSScreen) {
        let f = screen.frame, s = screen.backingScaleFactor
        if window.frame != f { window.setFrame(f, display: false) }
        guard f.size != size || s != scale else { return }
        size = f.size; scale = s; textKey = ""; fade = nil; flowKeys = nil
        CATransaction.begin(); CATransaction.setDisableActions(true)
        root.frame = CGRect(origin: .zero, size: size)
        for layer in [old, gradient] { layer.frame = root.bounds; layer.removeAllAnimations() }
        old.contents = nil
        gradient.opacity = 1
        gradient.contents = Picture.gradient(shown, canvas: size, width: pixels.w, height: pixels.h)
        for mask in masks { mask.contentsScale = s; mask.canvasHeight = size.height }
        CATransaction.commit()
    }

    /// Lays out the type for `date`. Only redraws when the day, the options, the screen or the language changed.
    func setText(date: Date, strip showStrip: Bool, info: Bool) {
        let d = Calendar.current.dateComponents([.year, .month, .day], from: date)
        let key = "\(d.year ?? 0)-\(d.month ?? 0)-\(d.day ?? 0) \(showStrip) \(info) \(size) \(scale) \(Locale.current.identifier)"
        guard key != textKey else { return }
        textKey = key
        let marks = Lettering.layout(canvas: size, date: date, strip: showStrip, info: info)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        for (i, m) in [marks.block, marks.strip].enumerated() {
            type[i].isHidden = m.isEmpty
            guard !m.isEmpty else { continue }
            type[i].frame = Lettering.bounds(m, canvasHeight: size.height).insetBy(dx: -6, dy: -6).integral    // 6 pt of room for antialiasing
            masks[i].frame = type[i].bounds
            masks[i].origin = type[i].frame.origin
            masks[i].marks = m
            masks[i].setNeedsDisplay()
        }
        CATransaction.commit()
    }

    /// Shows `p`. With seconds > 0 Core Animation cross-fades to it by itself; this process does nothing per frame.
    ///
    /// The fade is two still pictures, one above the other, and an opacity: that keeps Core Animation's dither. An animation
    /// of `contents` is blended without dither and shows bands for as long as it runs. The darker picture goes on top,
    /// because a faint light layer over a dark one still leaves contours.
    func show(_ p: Palette, seconds: CFTimeInterval) {
        guard p != shown else { return }
        var from = shown, fromImage = gradient.contents
        if flowKeys != nil {                                                   // leaving a flow: the screen is a blend of two pictures, so draw that blend as one
            fromImage = Picture.gradient(shown, canvas: size, width: pixels.w, height: pixels.h)
            flowKeys = nil
        } else if let f = fade {                                               // interrupted mid-fade: start from what is on screen now
            let t = Double(f.oldOnTop ? 1 - (old.presentation()?.opacity ?? 0) : gradient.presentation()?.opacity ?? 1)
            if t < 1 {
                from = f.from.mix(shown, t)
                fromImage = Picture.gradient(from, canvas: size, width: pixels.w, height: pixels.h)
            }
        }
        generation += 1
        let image = Picture.gradient(p, canvas: size, width: pixels.w, height: pixels.h), mine = generation
        CATransaction.begin(); CATransaction.setDisableActions(true)
        for layer in [old, gradient] { layer.removeAnimation(forKey: "fade") }
        gradient.opacity = 1
        if seconds > 0 {
            let oldOnTop = from.base.luminance < p.base.luminance
            CATransaction.setCompletionBlock { [weak self] in                  // the old picture is dropped once nothing of it shows
                MainActor.assumeIsolated { if let self, self.generation == mine { self.old.contents = nil; self.fade = nil } }
            }
            let a = CABasicAnimation(keyPath: "opacity")
            a.fromValue = oldOnTop ? 1 : 0; a.toValue = oldOnTop ? 0 : 1; a.duration = seconds
            a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            a.preferredFrameRateRange = Wall.slowRate
            (oldOnTop ? old : gradient).add(a, forKey: "fade")
            old.contents = fromImage
            old.opacity = oldOnTop ? 0 : 1                                     // where each layer rests when the fade is over
            gradient.zPosition = oldOnTop ? -1 : 0
            fade = (from, oldOnTop)
        } else { fade = nil; old.contents = nil }
        gradient.contents = image
        window.backgroundColor = NSColor(cgColor: p.base.cg()) ?? .black
        if p.ink != shown.ink {                                                // the type changes colour half-way, with a short fade of its own,
            let flip = min(0.3, seconds)                                       // so it is never the same colour as the background for long
            for tint in type {
                let now = tint.presentation()?.backgroundColor ?? tint.backgroundColor
                tint.removeAnimation(forKey: "ink")
                if flip > 0 {
                    let a = CABasicAnimation(keyPath: "backgroundColor")
                    a.fromValue = now; a.toValue = p.ink.cg(); a.duration = flip
                    a.beginTime = tint.convertTime(CACurrentMediaTime(), from: nil) + (seconds - flip) / 2
                    a.fillMode = .backwards
                    a.preferredFrameRateRange = Wall.slowRate
                    tint.add(a, forKey: "ink")
                }
                tint.backgroundColor = p.ink.cg()
            }
        }
        shown = p
        CATransaction.commit()
    }

    /// One small step of a flow. Two neighbouring key pictures stay loaded and only the upper one's opacity moves, so a step
    /// is a property change for the graphics chip and no drawing at all; a new picture is made only when a key is passed.
    func blend(_ a: Palette, _ b: Palette, _ f: Double) {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        if flowKeys?.a != a || flowKeys?.b != b {
            for layer in [old, gradient] { layer.removeAnimation(forKey: "fade") }
            generation += 1; fade = nil
            // the upper picture of the stretch just finished becomes the lower one of this
            old.contents = flowKeys?.b == a ? gradient.contents : Picture.gradient(a, canvas: size, width: pixels.w, height: pixels.h)
            gradient.contents = Picture.gradient(b, canvas: size, width: pixels.w, height: pixels.h)
            old.opacity = 1; gradient.zPosition = 0
            window.backgroundColor = NSColor(cgColor: b.base.cg()) ?? .black
            flowKeys = (a, b)
        }
        gradient.opacity = Float(f)
        shown = a.mix(b, f)
        for tint in type { tint.removeAnimation(forKey: "ink"); tint.backgroundColor = shown.ink.cg() }
        CATransaction.commit()
    }
}

// MARK: - The app

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    private var settings = Settings.load()
    private var walls: [CGDirectDisplayID: Wall] = [:]
    private var timer: Timer?
    private var status: NSStatusItem?
    private var panel: NSWindow?
    private var controls: Controls?
    private var synced = "", glideEnd = Date.distantPast, turningOff = false
    private var appearanceWatch: NSKeyValueObservation?
    /// Light or Dark, as the Mac is now. On a Mac whose appearance is set to Auto this turns at sunset and sunrise.
    private var isDark: Bool { NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua }
    private struct Controls { let swatches: [NSButton], wells: [NSColorWell], auto: NSButton, pace: NSPopUpButton, strip: NSButton, info: NSButton, login: NSButton }
    private let looks = Presets.ring + ["custom"]                              // everything that can be picked, in the order it is listed

    func applicationDidFinishLaunching(_ note: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength), menu = NSMenu()
        item.button?.image = NSImage(systemSymbolName: "sun.horizon.fill", accessibilityDescription: "Dusk Wallpaper")
        menu.delegate = self
        item.menu = menu
        status = item
        buildMainMenu()
        refresh(fade: 0)
        // Everything that can change the picture ends in refresh(), which is safe to call any number of times.
        let app = NotificationCenter.default, workspace = NSWorkspace.shared.notificationCenter
        let triggers: [(NotificationCenter, Notification.Name)] = [
            (app, NSApplication.didChangeScreenParametersNotification), (app, NSWindow.didChangeOcclusionStateNotification),
            (app, .NSCalendarDayChanged), (app, .NSSystemClockDidChange), (app, .NSSystemTimeZoneDidChange), (app, NSLocale.currentLocaleDidChangeNotification),
            (workspace, NSWorkspace.didWakeNotification), (workspace, NSWorkspace.screensDidWakeNotification)]
        for (center, name) in triggers {
            _ = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.refresh() } }
        }
        appearanceWatch = NSApp.observe(\.effectiveAppearance) { [weak self] _, _ in       // day turns to night, or back
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.refresh() } }
        }
        // A wallpaper starts with the Mac unless its owner has said otherwise: once it sits in an Applications folder it
        // registers itself, and again whenever a rebuild has cost it the registration. A copy run from anywhere else does not.
        let installed = Bundle.main.bundleURL.deletingLastPathComponent().lastPathComponent == "Applications"
        if settings.startAtLogin && installed && SMAppService.mainApp.status != .enabled { try? SMAppService.mainApp.register() }
        let event = NSAppleEventManager.shared().currentAppleEvent
        let atLogin = event?.eventID == kAEOpenApplication && event?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
        let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first?.launchDate
        let justLoggedIn = dock.map { Date().timeIntervalSince($0) < 120 } ?? false     // a second sign of a login start, should the event not say so
        if !atLogin && !justLoggedIn && !CommandLine.arguments.contains("--background") { showSettings() }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showSettings(); return false }

    /// Quitting while the settings are open only puts them away: the wallpaper stays up, as a wallpaper should.
    /// It ends when it is turned off, when it is told to quit while in the background, and when the Mac logs out, restarts or shuts down.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let event = NSAppleEventManager.shared().currentAppleEvent, why = AEKeyword(kAEQuitReason)     // the system says why it asks; a person does not
        let leaving = event?.attributeDescriptor(forKeyword: why) != nil || event?.paramDescriptor(forKeyword: why) != nil
        guard let panel, !turningOff, !leaving else { return .terminateNow }
        panel.close()
        return .terminateCancel
    }

    /// The one update. Keeps one window per display, the date current, the right picture on screen and at most one timer armed.
    private func refresh(fade: CFTimeInterval? = nil) {
        let now = Date(), dark = isDark, target = settings.palette(at: now, dark: dark)
        if glideEnd.timeIntervalSince(now) > 5 { glideEnd = .distantPast }     // the clock was set back: no glide lasts that long
        var present = Set<CGDirectDisplayID>()
        for screen in NSScreen.screens where screen.frame.width > 0 && screen.frame.height > 0 {
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else { continue }
            present.insert(id)
            if let wall = walls[id] { wall.fit(screen) } else { walls[id] = Wall(screen: screen, palette: target) }
        }
        if !present.isEmpty {                                                  // a sleeping Mac can report no displays; keep the windows then
            for (id, wall) in walls where !present.contains(id) { wall.window.close(); walls[id] = nil }
        }
        let visible = walls.values.contains { $0.isVisible }
        let step = settings.mode == .auto ? settings.flow(at: now, dark: dark) : nil
        var glide: CFTimeInterval = 0
        CATransaction.begin()                                                  // every display changes in the same frame, with one message to the window server
        for wall in walls.values {
            wall.setText(date: now, strip: settings.strip, info: settings.info)
            let crossing = wall.shown.isDark != target.isDark                  // between a light picture and a dark one
            if fade == nil, !crossing, now < glideEnd { continue }             // a glide is under way: stray notifications must not cut it short
            if let step, visible, timer != nil, fade == nil, !crossing {       // flowing: one more small step
                wall.blend(step.a, step.b, step.f)
            } else {                                                           // everything else is a glide, or unseen a plain change
                let seconds = !visible ? 0 : fade ?? (crossing ? 5 : 1.5)
                // a flow is met where it will have got to when the glide ends, as the very blend the steps then continue from
                let ahead = step == nil ? nil : settings.flow(at: now.addingTimeInterval(seconds), dark: dark)
                wall.show(ahead.map { $0.a.mix($0.b, $0.f) } ?? target, seconds: seconds)
                glide = max(glide, seconds)
            }
        }
        CATransaction.commit()
        if glide > 0 { glideEnd = now.addingTimeInterval(glide) }
        timer?.invalidate()
        timer = nil
        if let step, visible {                                                 // one shot, aimed at the next step once any glide is over; none at all while nobody can see it
            let next = Timer(fire: max(step.next, glideEnd), interval: 0, repeats: false) { [weak self] _ in MainActor.assumeIsolated { self?.refresh() } }
            next.tolerance = 0.01
            RunLoop.main.add(next, forMode: .common)
            timer = next
        }
        let look = settings.shownName(at: now, dark: dark) ?? "custom"
        if fade != nil || look != synced { synced = look; syncPanel() }         // the settings window only needs telling when something it shows changed
    }

    private func change(fade: CFTimeInterval?, _ edit: (inout Settings) -> Void) {
        edit(&settings)
        settings.save()
        refresh(fade: fade)
    }

    // MARK: Actions

    @objc private func toggleAuto() {
        let now = Date(), current = settings.shownName(at: now, dark: isDark)
        change(fade: 1.5) { s in
            if s.mode == .auto { s.mode = .preset; s.preset = current ?? s.preset; return }                // stop on what is showing
            s.mode = .auto; s.autoStart = now                                                              // or set off from it
            s.autoBase = Double(current.flatMap(Presets.day.firstIndex(of:)) ?? (current == "night" ? 1 : 0))
        }
    }
    @objc private func pickLook(_ sender: NSObject) {
        guard let name = (sender as? NSMenuItem)?.representedObject as? String ?? (sender as? NSView)?.identifier?.rawValue else { return }
        change(fade: 1.2) { if name == "custom" { $0.mode = .custom } else { $0.mode = .preset; $0.preset = name } }
    }
    @objc private func pickPace(_ sender: NSPopUpButton) {
        let now = Date(), here = settings.position(at: now), pace = TimeInterval(sender.selectedTag())
        guard Settings.paces.contains(pace) else { return }
        change(fade: 1.2) { $0.autoStart = now; $0.autoBase = here; $0.pace = pace }       // the flow carries on from where it is, at the new pace
    }
    @objc private func pickColour(_ sender: NSColorWell) {
        guard let c = sender.color.usingColorSpace(.displayP3), (0..<3).contains(sender.tag) else { return }
        change(fade: 0) { $0.custom[sender.tag] = RGB(c.redComponent, c.greenComponent, c.blueComponent); $0.mode = .custom }
    }
    @objc private func toggleStrip(_ sender: NSButton) { change(fade: nil) { $0.strip = sender.state == .on } }       // the type changes; the picture carries on
    @objc private func toggleInfo(_ sender: NSButton) { change(fade: nil) { $0.info = sender.state == .on } }
    @objc private func toggleLogin(_ sender: NSButton) {
        do { if sender.state == .on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
        catch { NSAlert(error: error).runModal() }
        sender.state = SMAppService.mainApp.status == .enabled ? .on : .off
        settings.startAtLogin = sender.state == .on
        settings.save()
    }
    @objc private func turnOff() { turningOff = true; NSApp.terminate(nil) }

    // MARK: Menus

    /// The menu-bar menu, made afresh each time it opens: Auto and where it is, the looks to pick from, Settings and Quit.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let now = Date(), dark = isDark, auto = settings.mode == .auto
        let shown = auto ? nil : settings.shownName(at: now, dark: dark) ?? "custom"       // while Auto runs it has the only tick
        let flow = menu.addItem(withTitle: "Flow Automatically", action: #selector(toggleAuto), keyEquivalent: "")
        flow.target = self
        flow.state = auto ? .on : .off
        if auto {
            let leg = Presets.leg(at: settings.position(at: now))
            menu.addItem(withTitle: dark ? "Night, its colours drifting" : "\(leg.from.capitalized)  →  \(leg.to.capitalized)", action: nil, keyEquivalent: "")
        }
        menu.addItem(.separator())
        for look in looks {
            let item = menu.addItem(withTitle: look == "custom" ? "Own Colours" : look.capitalized, action: #selector(pickLook(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = look
            item.state = look == shown ? .on : .off
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",").target = self
        menu.addItem(withTitle: "Turn Off Wallpaper", action: #selector(turnOff), keyEquivalent: "").target = self
    }

    private func buildMainMenu() {                                             // only seen while the settings window is open
        // macOS adds dictation and emoji items to an Edit menu by itself, and to one built in code several times over.
        UserDefaults.standard.register(defaults: ["NSDisabledDictationMenuItem": true, "NSDisabledCharacterPaletteMenuItem": true])
        let main = NSMenu(), appMenu = NSMenu(), file = NSMenu(title: "File"), edit = NSMenu(title: "Edit")
        appMenu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Dusk Wallpaper", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")     // puts the settings away; see applicationShouldTerminate
        file.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        for (name, action, key) in [("Cut", #selector(NSText.cut(_:)), "x"), ("Copy", #selector(NSText.copy(_:)), "c"),      // so a colour code can be pasted
                                    ("Paste", #selector(NSText.paste(_:)), "v"), ("Select All", #selector(NSText.selectAll(_:)), "a")] {
            edit.addItem(withTitle: name, action: action, keyEquivalent: key)
        }
        for sub in [appMenu, file, edit] { let item = NSMenuItem(); item.submenu = sub; main.addItem(item) }
        NSApp.mainMenu = main
    }

    // MARK: Settings window (built when opened, released when closed; the app shows in the Dock only while it is open)

    @objc private func showSettings() {
        if panel == nil { panel = makePanel() }
        controls?.login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        panel?.makeKeyAndOrderFront(nil)
    }
    func windowWillClose(_ note: Notification) {
        if NSColorPanel.sharedColorPanelExists { NSColorPanel.shared.close() }
        NSApp.setActivationPolicy(.accessory)
        panel = nil
        controls = nil
    }

    private func makePanel() -> NSWindow {
        func label(_ s: String, bold: Bool = false, small: Bool = false) -> NSTextField {
            let l = NSTextField(labelWithString: s)
            l.font = bold ? .boldSystemFont(ofSize: 13) : .systemFont(ofSize: small ? 11 : 13)
            if small { l.textColor = .secondaryLabelColor }
            return l
        }
        func row(_ views: [NSView], spacing: CGFloat = 10) -> NSStackView { let s = NSStackView(views: views); s.spacing = spacing; return s }
        func rule() -> NSBox { let b = NSBox(); b.boxType = .separator; return b }
        func indent(_ v: NSView) -> NSStackView { let s = row([v]); s.edgeInsets = NSEdgeInsets(top: 0, left: 20, bottom: 0, right: 0); return s }

        let swatches = looks.map { look -> NSButton in
            let b = NSButton(title: look == "custom" ? "Own" : look.capitalized, target: self, action: #selector(pickLook(_:)))
            b.identifier = NSUserInterfaceItemIdentifier(look)
            b.isBordered = false; b.imagePosition = .imageAbove; b.font = .systemFont(ofSize: 11)
            return b
        }
        let auto = NSButton(checkboxWithTitle: "Flow through the gradients, a new one", target: self, action: #selector(toggleAuto))
        let pace = NSPopUpButton(frame: .zero, pullsDown: false)               // the checkbox and this read as one sentence
        pace.target = self; pace.action = #selector(pickPace(_:))
        for seconds in Settings.paces {
            pace.addItem(withTitle: seconds < 60 ? "every \(Int(seconds)) seconds" : seconds == 60 ? "every minute" : "every \(Int(seconds / 60)) minutes")
            pace.lastItem?.tag = Int(seconds)
        }
        let flow = row([auto, pace], spacing: 6)
        let wells = (0..<3).map { i -> NSColorWell in
            let w = NSColorWell(frame: NSRect(x: 0, y: 0, width: 44, height: 24))
            w.tag = i; w.target = self; w.action = #selector(pickColour(_:)); w.supportsAlpha = false
            w.toolTip = ["Bottom left", "Top right", "Lower right"][i]
            w.widthAnchor.constraint(equalToConstant: 44).isActive = true
            w.heightAnchor.constraint(equalToConstant: 24).isActive = true
            return w
        }
        let strip = NSButton(checkboxWithTitle: "Line of days", target: self, action: #selector(toggleStrip(_:)))
        let info = NSButton(checkboxWithTitle: "Week number and days left", target: self, action: #selector(toggleInfo(_:)))
        let login = NSButton(checkboxWithTitle: "Start at login", target: self, action: #selector(toggleLogin(_:)))
        let off = NSButton(title: "Turn Off Wallpaper", target: self, action: #selector(turnOff))

        let stack = NSStackView(views: [
            label("Gradient", bold: true), row(swatches), row([label("Own colours")] + wells),
            flow, indent(label("Light by day, Night after dark: it follows this Mac's appearance.", small: true)), rule(),
            label("Show", bold: true), strip, info, rule(),
            login, label("The wallpaper stays on when you close or quit this app.", small: true), off])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 24, bottom: 20, right: 24)
        stack.setCustomSpacing(4, after: flow)
        stack.widthAnchor.constraint(equalToConstant: 460).isActive = true
        let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Dusk Wallpaper"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = stack
        controls = Controls(swatches: swatches, wells: wells, auto: auto, pace: pace, strip: strip, info: info, login: login)
        syncPanel()                                                            // fill everything in before measuring
        window.setContentSize(stack.fittingSize)
        window.center()
        return window
    }

    /// Makes the settings window say what is true right now.
    private func syncPanel() {
        guard let c = controls else { return }
        let shown = settings.shownName(at: Date(), dark: isDark) ?? "custom"
        for b in c.swatches {                                                  // the ring marks what is on screen, while Auto runs too
            let look = b.identifier?.rawValue ?? ""
            b.image = Self.swatch(look == "custom" ? Palette(custom: settings.custom) : Presets.palette(look), selected: look == shown)
        }
        for (well, rgb) in zip(c.wells, settings.custom) where !well.isActive { well.color = NSColor(cgColor: rgb.cg()) ?? .gray }
        c.auto.state = settings.mode == .auto ? .on : .off
        c.pace.selectItem(withTag: Int(settings.pace))
        c.pace.isEnabled = settings.mode == .auto
        c.strip.state = settings.strip ? .on : .off
        c.info.state = settings.info ? .on : .off
    }

    /// The settings window drawn off screen as a PNG at twice its size in points, for checks and for the readme
    /// (nothing in this app can see the real screen).
    func settingsPNG() -> Data? {
        let window = makePanel()
        guard let view = window.contentView else { return nil }
        controls?.login.state = settings.startAtLogin ? .on : .off
        view.wantsLayer = true                                                 // give the picture the window's own background, light or dark
        view.effectiveAppearance.performAsCurrentDrawingAppearance { view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor }
        view.layoutSubtreeIfNeeded()
        guard let image = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(view.bounds.width) * 2, pixelsHigh: Int(view.bounds.height) * 2, bitsPerSample: 8,
                                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        image.size = view.bounds.size
        view.cacheDisplay(in: view.bounds, to: image)
        return image.representation(using: .png, properties: [:])
    }

    /// AppKit may draw an image on any thread, so this must not be tied to the main actor.
    nonisolated private static func swatch(_ p: Palette, selected: Bool) -> NSImage {
        NSImage(size: NSSize(width: 46, height: 46), flipped: false) { rect in
            let circle = NSBezierPath(ovalIn: rect.insetBy(dx: 5, dy: 5))
            NSGradient(colors: [p.c[1], p.c[2], p.c[0]].map { NSColor(cgColor: $0.cg()) ?? .gray })?.draw(in: circle, angle: 225)
            NSColor.white.withAlphaComponent(0.5).setStroke()
            circle.stroke()
            if selected {
                let ring = NSBezierPath(ovalIn: rect.insetBy(dx: 1.5, dy: 1.5))
                ring.lineWidth = 2
                NSColor.controlAccentColor.setStroke()
                ring.stroke()
            }
            return true
        }
    }
}

// MARK: - Start

func render(_ args: [String]) -> Int32 {
    func fail(_ why: String) -> Int32 { fputs("DuskWallpaper --render: \(why) (the options are listed at the top of main.swift)\n", stderr); return 2 }
    func value(_ flag: String) -> String? { args.firstIndex(of: flag).flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil } }
    func triples(_ text: String, _ count: Int) -> [RGB]? {
        let parts = text.split(separator: ";").map { $0.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) } }
        return parts.count == count && parts.allSatisfy({ $0.count == 3 }) ? parts.map { RGB($0[0], $0[1], $0[2]) } : nil
    }
    guard let out = args.first, !out.hasPrefix("--") else { return fail("no output file given") }
    var canvas = CGSize(width: 1800, height: 1169), scale = 2.0, palette = Presets.palette("dusk"), date = Date()
    if let v = value("--size") {
        let s = v.split(separator: "x").compactMap { Double($0) }
        guard s.count == 2, s.allSatisfy({ $0 >= 16 && $0 <= 16384 }) else { return fail("cannot use --size \(v)") }
        canvas = CGSize(width: s[0], height: s[1])
    }
    if let v = value("--scale") { guard let s = Double(v), s >= 0.1, s <= 8 else { return fail("cannot use --scale \(v)") }; scale = s }
    guard max(canvas.width, canvas.height) * scale <= 16384 else { return fail("that picture would be larger than 16384 pixels") }
    if let v = value("--palette") { guard let p = Presets.all[v] else { return fail("no palette called \(v)") }; palette = p }
    if let v = value("--at") { guard let x = Double(v), x.isFinite else { return fail("cannot use --at \(v)") }; palette = Presets.picture(at: x, dark: args.contains("--dark")) }
    if let v = value("--p3") { guard let c = triples(v, 6) else { return fail("--p3 needs six r,g,b triples") }; palette = Palette(c) }
    if let v = value("--custom") { guard let c = triples(v, 3) else { return fail("--custom needs three r,g,b triples") }; palette = Palette(custom: c) }
    if let v = value("--date") {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd HH:mm"
        guard let d = f.date(from: v + " 12:00") else { return fail("cannot read --date \(v); use 2026-11-11") }
        date = d
    }
    return Picture.writePNG(to: URL(filePath: out), palette: palette, canvas: canvas, scale: scale, date: date,
                            strip: !args.contains("--no-strip"), info: !args.contains("--no-info"), text: !args.contains("--no-text")) ? 0 : 1
}

let arguments = Array(CommandLine.arguments.dropFirst())
if let i = arguments.firstIndex(of: "--render") { exit(render(Array(arguments[(i + 1)...]))) }
let app = NSApplication.shared
if let i = arguments.firstIndex(of: "--render-settings"), i + 1 < arguments.count {
    let saved: Void? = try? AppDelegate().settingsPNG()?.write(to: URL(filePath: arguments[i + 1]))
    exit(saved == nil ? 1 : 0)
}
// A mistyped command must never start a second wallpaper, and neither must a second launch.
if arguments.contains(where: { $0.hasPrefix("--") && $0 != "--background" }) { exit(2) }
let me = NSRunningApplication.current
if NSRunningApplication.runningApplications(withBundleIdentifier: me.bundleIdentifier ?? "").contains(where: { $0 != me && kill($0.processIdentifier, 0) == 0 }) { exit(0) }
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
