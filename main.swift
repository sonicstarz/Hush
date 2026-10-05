// Hush — a menu bar app that centers the focused window and melts everything
// else into a slowly drifting bokeh field. Click the icon (or ⌃⌥F) to enter;
// click the background (or ⌃⌥F again) to leave.

import Cocoa
import Carbon.HIToolbox
import ServiceManagement

// MARK: - Deterministic randomness (so every overlay window draws the same scene)

struct SeededRNG: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 { // splitmix64
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    mutating func r(_ range: ClosedRange<CGFloat>) -> CGFloat { CGFloat.random(in: range, using: &self) }
}

// MARK: - Bokeh scene

/// Draws a blur that morphs into bokeh. The scene is laid out in *screen* space,
/// so several windows on the same screen (main overlay + menu bar / Dock strips)
/// line up seamlessly.
final class BokehView: NSView {
    private let blur = NSVisualEffectView()
    private let sceneHost = NSView()

    init(windowFrame: NSRect, screen: NSScreen, seed: UInt64, epoch: CFTimeInterval) {
        super.init(frame: NSRect(origin: .zero, size: windowFrame.size))
        wantsLayer = true

        blur.frame = bounds
        blur.autoresizingMask = [.width, .height]
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.alphaValue = 0
        addSubview(blur)

        sceneHost.frame = bounds
        sceneHost.autoresizingMask = [.width, .height]
        sceneHost.wantsLayer = true
        addSubview(sceneHost)

        let sf = screen.frame
        let scene = CALayer()
        scene.frame = CGRect(x: sf.minX - windowFrame.minX, y: sf.minY - windowFrame.minY,
                             width: sf.width, height: sf.height)
        sceneHost.layer!.addSublayer(scene)
        sceneHost.layer!.masksToBounds = true
        buildScene(in: scene, size: sf.size, scale: screen.backingScaleFactor, seed: seed, epoch: epoch)

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.45
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            blur.animator().alphaValue = 1
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    private func buildScene(in scene: CALayer, size: CGSize, scale: CGFloat, seed: UInt64, epoch: CFTimeInterval) {
        var rng = SeededRNG(seed: seed)
        let easeOut = CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)

        // Whole scene fades in over the blur — the "morph".
        scene.opacity = 1
        let sceneIn = CABasicAnimation(keyPath: "opacity")
        sceneIn.fromValue = 0; sceneIn.toValue = 1
        sceneIn.beginTime = epoch + 0.25
        sceneIn.duration = 1.6
        sceneIn.timingFunction = easeOut
        sceneIn.fillMode = .backwards
        scene.add(sceneIn, forKey: "in")

        // Deep base wash.
        let base = CAGradientLayer()
        base.frame = CGRect(origin: .zero, size: size)
        base.colors = [rgb(0.04, 0.05, 0.13), rgb(0.12, 0.06, 0.20), rgb(0.20, 0.08, 0.14)]
        base.startPoint = CGPoint(x: 0, y: 0)
        base.endPoint = CGPoint(x: 1, y: 1)
        base.opacity = 1
        scene.addSublayer(base)

        let palette: [(CGFloat, CGFloat, CGFloat)] = [
            (1.00, 0.76, 0.42), // amber
            (1.00, 0.52, 0.55), // rose
            (0.66, 0.58, 1.00), // lavender
            (0.42, 0.82, 0.96), // sky
            (1.00, 0.92, 0.80), // cream
        ]
        func pick() -> (CGFloat, CGFloat, CGFloat) { palette[Int.random(in: 0..<palette.count, using: &rng)] }

        // Big soft color glows.
        for _ in 0..<5 {
            let c = pick()
            let r = rng.r(0.25...0.45) * max(size.width, size.height)
            let p = CGPoint(x: rng.r(0...size.width), y: rng.r(0...size.height))
            let glow = disc(radius: r, color: c, alpha: rng.r(0.16...0.28), scale: scale)
            glow.position = p
            scene.addSublayer(glow)
            drift(glow, from: p, amount: r * 0.35, duration: rng.r(50...80), rng: &rng, epoch: epoch)
        }

        // Bokeh discs: big, heavily out-of-focus orbs.
        let count = Int(size.width * size.height / 70_000).clamped(to: 18...40)
        for i in 0..<count {
            let c = pick()
            let near = i % 3 == 0
            let r = near ? rng.r(110...230) : rng.r(40...110)
            let alpha = near ? rng.r(0.14...0.26) : rng.r(0.22...0.40)
            let p = CGPoint(x: rng.r(-40...size.width + 40), y: rng.r(-40...size.height + 40))
            let d = disc(radius: r, color: c, alpha: alpha, scale: scale)
            d.position = p
            scene.addSublayer(d)

            drift(d, from: p, amount: near ? 90 : 55, duration: rng.r(28...60), rng: &rng, epoch: epoch)

            let twinkle = CABasicAnimation(keyPath: "opacity")
            twinkle.fromValue = 1; twinkle.toValue = rng.r(0.35...0.75)
            twinkle.duration = Double(rng.r(3...8))
            twinkle.autoreverses = true
            twinkle.repeatCount = .infinity
            twinkle.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            twinkle.beginTime = epoch
            twinkle.timeOffset = Double(rng.r(0...8))
            d.add(twinkle, forKey: "twinkle")

            let grow = CABasicAnimation(keyPath: "transform.scale")
            grow.fromValue = 0.15; grow.toValue = 1
            grow.beginTime = epoch + 0.3 + Double(rng.r(0...0.6))
            grow.duration = Double(rng.r(1.4...2.2))
            grow.timingFunction = easeOut
            grow.fillMode = .backwards
            d.add(grow, forKey: "grow")
        }

        // Gentle vignette pulls the eye to the middle.
        let vignette = CAGradientLayer()
        vignette.type = .radial
        vignette.frame = CGRect(origin: .zero, size: size)
        vignette.startPoint = CGPoint(x: 0.5, y: 0.5)
        vignette.endPoint = CGPoint(x: 1.15, y: 1.15)
        vignette.colors = [CGColor(gray: 0, alpha: 0), CGColor(gray: 0, alpha: 0.55)]
        vignette.locations = [0.45, 1]
        scene.addSublayer(vignette)
    }

    private func disc(radius r: CGFloat, color c: (CGFloat, CGFloat, CGFloat), alpha a: CGFloat,
                      scale: CGFloat) -> CAGradientLayer {
        let g = CAGradientLayer()
        g.type = .radial
        g.bounds = CGRect(x: 0, y: 0, width: r * 2, height: r * 2)
        g.startPoint = CGPoint(x: 0.5, y: 0.5)
        g.endPoint = CGPoint(x: 1, y: 1)
        g.contentsScale = scale
        // Gaussian-ish falloff — no hard edge anywhere.
        let falloff: [(CGFloat, NSNumber)] = [(1, 0), (0.9, 0.2), (0.62, 0.45), (0.3, 0.7), (0.1, 0.87), (0, 1)]
        g.colors = falloff.map { rgb(c.0, c.1, c.2, a * $0.0) }
        g.locations = falloff.map { $0.1 }
        return g
    }

    private func drift(_ layer: CALayer, from p: CGPoint, amount: CGFloat, duration: CGFloat,
                       rng: inout SeededRNG, epoch: CFTimeInterval) {
        var pts = [p]
        for _ in 0..<4 { pts.append(CGPoint(x: p.x + rng.r(-amount...amount), y: p.y + rng.r(-amount...amount))) }
        pts.append(p)
        let a = CAKeyframeAnimation(keyPath: "position")
        a.values = pts.map { NSValue(point: $0) }
        a.calculationMode = .cubicPaced
        a.duration = Double(duration)
        a.repeatCount = .infinity
        a.beginTime = epoch
        a.timeOffset = Double(rng.r(0...duration))
        layer.add(a, forKey: "drift")
    }

    private func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
        CGColor(srgbRed: r, green: g, blue: b, alpha: a)
    }
}

extension Comparable {
    func clamped(to r: ClosedRange<Self>) -> Self { min(max(self, r.lowerBound), r.upperBound) }
}

// MARK: - Overlay window

final class OverlayPanel: NSPanel {
    var onClick: (() -> Void)?

    init(frame: NSRect, level: NSWindow.Level) {
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        setFrame(frame, display: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        self.level = level
        collectionBehavior = [.fullScreenAuxiliary, .ignoresCycle]
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown || event.type == .rightMouseDown { onClick?(); return }
        super.sendEvent(event)
    }
}

// MARK: - Accessibility helpers

enum AX {
    static func value(_ el: AXUIElement, _ attr: String) -> AXValue? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr as CFString, &ref) == .success, let v = ref else { return nil }
        return (v as! AXValue)
    }
    static func origin(_ el: AXUIElement) -> CGPoint? {
        var p = CGPoint.zero
        guard let v = value(el, kAXPositionAttribute), AXValueGetValue(v, .cgPoint, &p) else { return nil }
        return p
    }
    static func size(_ el: AXUIElement) -> CGSize? {
        var s = CGSize.zero
        guard let v = value(el, kAXSizeAttribute), AXValueGetValue(v, .cgSize, &s) else { return nil }
        return s
    }
    static func setOrigin(_ el: AXUIElement, _ p: CGPoint) {
        var p = p
        AXUIElementSetAttributeValue(el, kAXPositionAttribute as CFString, AXValueCreate(.cgPoint, &p)!)
    }
    static func setSize(_ el: AXUIElement, _ s: CGSize) {
        var s = s
        AXUIElementSetAttributeValue(el, kAXSizeAttribute as CFString, AXValueCreate(.cgSize, &s)!)
    }
    static func focusedWindow(pid: pid_t) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        for attr in [kAXFocusedWindowAttribute, kAXMainWindowAttribute] {
            var ref: CFTypeRef?
            if AXUIElementCopyAttributeValue(app, attr as CFString, &ref) == .success, let w = ref {
                return (w as! AXUIElement)
            }
        }
        return nil
    }
}

/// Front-most normal-layer window of an app (window numbers are global, so we can order relative to it).
func frontWindowID(pid: pid_t) -> Int? {
    guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] else { return nil }
    for w in list where (w[kCGWindowOwnerPID as String] as? pid_t) == pid && (w[kCGWindowLayer as String] as? Int) == 0 {
        if let b = w[kCGWindowBounds as String] as? [String: CGFloat], (b["Width"] ?? 0) > 60, (b["Height"] ?? 0) > 60 {
            return w[kCGWindowNumber as String] as? Int
        }
    }
    return nil
}

// MARK: - Focus mode

final class FocusController {
    private(set) var isActive = false
    private var lowers: [OverlayPanel] = []   // below the focused window
    private var uppers: [OverlayPanel] = []   // over the menu bar / Dock
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var target: (el: AXUIElement, origin: CGPoint, size: CGSize, placedOrigin: CGPoint, placedSize: CGSize)?
    private var moveTimer: Timer?

    func toggle() { isActive ? stop() : start() }

    func start() {
        guard !isActive else { return }
        isActive = true

        let me = ProcessInfo.processInfo.processIdentifier
        let front = NSWorkspace.shared.frontmostApplication
        let pid = (front?.processIdentifier).flatMap { $0 == me ? nil : $0 }

        let seed = UInt64.random(in: 0...UInt64.max)
        let epoch = CACurrentMediaTime() + 0.03
        let chromeLevel = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue - 1)

        for screen in NSScreen.screens {
            let f = screen.frame, v = screen.visibleFrame
            lowers.append(makePanel(frame: f, level: .normal, screen: screen, seed: seed, epoch: epoch))
            // Strips that sit above the menu bar and Dock so they vanish into the bokeh too.
            let strips = [
                NSRect(x: f.minX, y: v.maxY, width: f.width, height: f.maxY - v.maxY),
                NSRect(x: f.minX, y: f.minY, width: f.width, height: v.minY - f.minY),
                NSRect(x: f.minX, y: v.minY, width: v.minX - f.minX, height: v.height),
                NSRect(x: v.maxX, y: v.minY, width: f.maxX - v.maxX, height: v.height),
            ]
            for r in strips where r.width > 0.5 && r.height > 0.5 {
                uppers.append(makePanel(frame: r, level: chromeLevel, screen: screen, seed: seed, epoch: epoch))
            }
        }

        if let pid, let wid = frontWindowID(pid: pid) {
            lowers.forEach { $0.order(.below, relativeTo: wid) }
        } else {
            lowers.forEach { $0.orderFrontRegardless() }
        }
        uppers.forEach { $0.orderFrontRegardless() }

        if let pid { centerFocusedWindow(pid: pid) }

        let ws = NSWorkspace.shared.notificationCenter
        observers.append((ws, ws.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] n in
            guard let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.processIdentifier != me else { return }
            // Focus follows you: keep whatever app you switch to above the bokeh.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                guard let self, self.isActive, let wid = frontWindowID(pid: app.processIdentifier) else { return }
                self.lowers.forEach { $0.order(.below, relativeTo: wid) }
            }
        }))
        observers.append((ws, ws.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.stop()
        }))
        let nc = NotificationCenter.default
        observers.append((nc, nc.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            self?.stop()
        }))
    }

    func stop() {
        guard isActive else { return }
        isActive = false
        observers.forEach { $0.0.removeObserver($0.1) }
        observers.removeAll()

        // Put the window back where it was, unless you've moved it since.
        if let t = target, let now = AX.origin(t.el),
           abs(now.x - t.placedOrigin.x) < 3, abs(now.y - t.placedOrigin.y) < 3 {
            if t.size != t.placedSize { AX.setSize(t.el, t.size) }
            animateWindow(t.el, from: now, to: t.origin, duration: 0.4)
        }
        target = nil

        let panels = lowers + uppers
        lowers.removeAll(); uppers.removeAll()
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.55
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panels.forEach { $0.animator().alphaValue = 0 }
        }, completionHandler: {
            panels.forEach { $0.orderOut(nil) }
        })
    }

    private func makePanel(frame: NSRect, level: NSWindow.Level, screen: NSScreen, seed: UInt64, epoch: CFTimeInterval) -> OverlayPanel {
        let p = OverlayPanel(frame: frame, level: level)
        p.contentView = BokehView(windowFrame: frame, screen: screen, seed: seed, epoch: epoch)
        p.onClick = { [weak self] in self?.stop() }
        return p
    }

    private func centerFocusedWindow(pid: pid_t) {
        guard AXIsProcessTrusted(), let el = AX.focusedWindow(pid: pid),
              let origin = AX.origin(el), let size = AX.size(el),
              let primaryH = NSScreen.screens.first?.frame.height else { return }

        // AX uses top-left origin; Cocoa uses bottom-left.
        let cocoa = NSRect(x: origin.x, y: primaryH - origin.y - size.height, width: size.width, height: size.height)
        let screen = NSScreen.screens.first { $0.frame.contains(NSPoint(x: cocoa.midX, y: cocoa.midY)) } ?? NSScreen.main!
        let f = screen.frame, v = screen.visibleFrame.insetBy(dx: 8, dy: 8)

        var newSize = size
        newSize.width = min(newSize.width, v.width)
        newSize.height = min(newSize.height, v.height)
        if newSize != size { AX.setSize(el, newSize) }

        // True center of the screen, nudged only as much as needed to clear the menu bar / Dock area.
        var x = f.midX - newSize.width / 2
        var y = f.midY - newSize.height / 2
        x = x.clamped(to: v.minX...max(v.minX, v.maxX - newSize.width))
        y = y.clamped(to: v.minY...max(v.minY, v.maxY - newSize.height))
        let dest = CGPoint(x: x.rounded(), y: (primaryH - y - newSize.height).rounded())

        target = (el, origin, size, dest, newSize)
        animateWindow(el, from: origin, to: dest, duration: 0.5)
    }

    private func animateWindow(_ el: AXUIElement, from a: CGPoint, to b: CGPoint, duration: Double) {
        moveTimer?.invalidate()
        let start = CACurrentMediaTime()
        moveTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] timer in
            let t = min(1, (CACurrentMediaTime() - start) / duration)
            let e = 1 - pow(1 - t, 3) // ease-out cubic
            AX.setOrigin(el, CGPoint(x: (a.x + (b.x - a.x) * e).rounded(), y: (a.y + (b.y - a.y) * e).rounded()))
            if t >= 1 { timer.invalidate(); self?.moveTimer = nil }
        }
    }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate {
    let focus = FocusController()
    var statusItem: NSStatusItem!
    var hotKeyRef: EventHotKeyRef?

    func applicationDidFinishLaunching(_ note: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let img = NSImage(systemSymbolName: "camera.aperture", accessibilityDescription: "Hush")
        img?.isTemplate = true
        statusItem.button?.image = img
        statusItem.button?.target = self
        statusItem.button?.action = #selector(clicked)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])

        registerHotKey()

        if !AXIsProcessTrusted() {
            AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary)
        }
    }

    @objc func clicked() {
        let e = NSApp.currentEvent
        if e?.type == .rightMouseUp || e?.modifierFlags.contains(.control) == true {
            showMenu()
        } else {
            focus.toggle()
        }
    }

    private func showMenu() {
        let menu = NSMenu()
        let hint = NSMenuItem(title: "Click icon or ⌃⌥F to focus", action: nil, keyEquivalent: "")
        hint.isEnabled = false
        menu.addItem(hint)
        menu.addItem(.separator())
        let login = NSMenuItem(title: "Open at Login", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        if !AXIsProcessTrusted() {
            let ax = NSMenuItem(title: "Grant Accessibility (to center windows)…", action: #selector(openAX), keyEquivalent: "")
            ax.target = self
            menu.addItem(ax)
        }
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Hush", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc func toggleLogin() {
        let s = SMAppService.mainApp
        try? (s.status == .enabled ? s.unregister() : s.register())
    }

    @objc func openAX() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    private func registerHotKey() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { (NSApp.delegate as? AppDelegate)?.focus.toggle() }
            return noErr
        }, 1, &spec, nil, nil)
        RegisterEventHotKey(UInt32(kVK_ANSI_F), UInt32(controlKey | optionKey),
                            EventHotKeyID(signature: OSType(0x4855_5348), id: 1), // 'HUSH'
                            GetApplicationEventTarget(), 0, &hotKeyRef)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
