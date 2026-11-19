import SwiftUI
import os

// MARK: - Liquid Glass UI System (iOS 26 .glassEffect + Material fallback)

struct LRLiquidGlassBackground<S: InsettableShape>: ViewModifier {
    let shape: S
    var interactive: Bool = false
    var tint: Color? = nil

    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            if let tint {
                if interactive {
                    content.glassEffect(.regular.tint(tint.opacity(0.18)).interactive(), in: shape)
                } else {
                    content.glassEffect(.regular.tint(tint.opacity(0.18)), in: shape)
                }
            } else {
                if interactive {
                    content.glassEffect(.regular.interactive(), in: shape)
                } else {
                    content.glassEffect(.regular, in: shape)
                }
            }
        } else {
            fallback(content)
        }
        #else
        fallback(content)
        #endif
    }

    @ViewBuilder
    private func fallback(_ content: Content) -> some View {
        content
            .background(shape.fill(.ultraThinMaterial))
            .overlay(
                shape.strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.32), Color.white.opacity(0.06)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.75
                )
            )
            .shadow(color: Color.black.opacity(0.08), radius: 10, y: 4)
    }
}

extension View {
    func lrLiquidGlass(cornerRadius: CGFloat = 20, interactive: Bool = false, tint: Color? = nil) -> some View {
        modifier(LRLiquidGlassBackground(shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous), interactive: interactive, tint: tint))
    }

    func lrLiquidGlassCapsule(interactive: Bool = false, tint: Color? = nil) -> some View {
        modifier(LRLiquidGlassBackground(shape: Capsule(), interactive: interactive, tint: tint))
    }
}

struct LRAmbientGlassBackdrop: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
            RadialGradient(
                colors: [Color.blue.opacity(scheme == .dark ? 0.22 : 0.12), .clear],
                center: .topLeading,
                startRadius: 20,
                endRadius: 420
            )
            RadialGradient(
                colors: [Color.indigo.opacity(scheme == .dark ? 0.20 : 0.10), .clear],
                center: .bottomTrailing,
                startRadius: 20,
                endRadius: 440
            )
            RadialGradient(
                colors: [Color.cyan.opacity(scheme == .dark ? 0.14 : 0.08), .clear],
                center: .center,
                startRadius: 10,
                endRadius: 360
            )
        }
        .ignoresSafeArea()
    }
}

/// iOS-style squircle app icon with glossy top sheen, inner specular rim, and hierarchical symbol.
struct LRIOSIcon: View {
    let symbol: String
    let colors: [Color]
    var size: CGFloat = 44
    var badge: Bool = false

    private var cornerRadius: CGFloat { size * 0.225 }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        ZStack {
            shape
                .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
            shape
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.32), Color.white.opacity(0.06), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            Image(systemName: symbol)
                .font(.system(size: size * 0.44, weight: .semibold, design: .rounded))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.white)
                .shadow(color: Color.black.opacity(0.18), radius: 2, y: 1)
        }
        .frame(width: size, height: size)
        .overlay(
            shape.strokeBorder(
                LinearGradient(
                    colors: [Color.white.opacity(0.45), Color.white.opacity(0.08)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 0.75
            )
        )
        .overlay(alignment: .topTrailing) {
            if badge {
                Circle()
                    .fill(Color.green)
                    .frame(width: max(10, size * 0.22), height: max(10, size * 0.22))
                    .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 2))
                    .offset(x: 3, y: -3)
            }
        }
        .shadow(color: (colors.last ?? .black).opacity(0.28), radius: size * 0.13, y: size * 0.07)
    }
}

/// Compact desktop status for the Home header. "Ready" is reported only when
/// the session says the desktop passed its readiness checks and painted a
/// frame; a running X server alone is "Starting".
struct HomeStatus: View {
    enum Phase: Equatable { case off, stopped, starting, ready, degraded }
    let phase: Phase
    var open: (() -> Void)?
    var stop: (() -> Void)?
    private var color: Color {
        switch phase { case .ready: return .green; case .degraded: return .yellow; case .starting: return .orange; case .stopped: return .gray; case .off: return .red }
    }
    private var title: String {
        switch phase { case .ready: return "Ready"; case .degraded: return "Limited"; case .starting: return "Starting"; case .stopped: return "Stopped"; case .off: return "Linux off" }
    }
    var body: some View {
        Menu {
            if let open { Button { open() } label: { Label(phase == .stopped ? "Open Desktop" : "Show Desktop", systemImage: "desktopcomputer") } }
            if let stop { Button(role: .destructive) { stop() } label: { Label("Stop Desktop", systemImage: "power") } }
        } label: {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous).fill(color.opacity(0.20)).frame(width: 28, height: 28)
                    if phase == .starting { ProgressView().scaleEffect(0.6).tint(color) }
                    else { Image(systemName: phase == .off ? "power" : "desktopcomputer").font(.system(size: 13, weight: .semibold)).foregroundColor(color) }
                }
                Text(title).font(.subheadline.weight(.semibold)).foregroundColor(.primary)
                Circle().fill(color).frame(width: 7, height: 7)
            }
            .padding(.leading, 6).padding(.trailing, 12).padding(.vertical, 6)
            .lrLiquidGlassCapsule(interactive: true, tint: color)
        }
        .disabled(open == nil && stop == nil)
        .accessibilityLabel("Desktop status: \(title)")
        .animation(.easeInOut(duration: 0.25), value: phase)
    }
}

/// Rounded-square app tile with a label underneath.
struct HomeTile: View {
    let title: String
    let symbol: String
    let colors: [Color]
    var large = false
    var badge = false
    @Environment(\.horizontalSizeClass) private var sizeClass
    var body: some View {
        if !large && sizeClass == .regular {
            HStack(spacing: 12) {
                icon(size: 44)
                Text(title).font(.subheadline.weight(.semibold)).foregroundColor(.primary).lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }
            .padding(12).frame(maxWidth: .infinity)
            .lrLiquidGlass(cornerRadius: 18, interactive: true)
        } else if large {
            HStack(spacing: 12) {
                icon(size: 46)
                Text(title).font(.headline).foregroundColor(.primary).lineLimit(title.count > 10 ? 2 : 1).minimumScaleFactor(0.85)
                    .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(14).frame(maxWidth: .infinity)
            .lrLiquidGlass(cornerRadius: 20, interactive: true)
        } else {
            VStack(spacing: 7) {
                icon(size: 60)
                Text(title).font(.caption.weight(.medium)).foregroundColor(.primary).lineLimit(1).minimumScaleFactor(0.8)
            }
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .lrLiquidGlass(cornerRadius: 18, interactive: true)
        }
    }
    private func icon(size: CGFloat) -> some View {
        LRIOSIcon(symbol: symbol, colors: colors, size: size, badge: badge)
    }
}

struct HomeTileStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Running and recent long tasks with their real state and elapsed time.
struct HomeTasks: View {
    @ObservedObject var center: LongTaskCenter
    var body: some View {
        if !center.entries.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Tasks").font(.headline)
                ForEach(center.entries.prefix(4)) { entry in
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 9, style: .continuous).fill(color(entry).opacity(0.18)).frame(width: 34, height: 34)
                                if entry.ended == nil && entry.state != .pausedByIOS { ProgressView().scaleEffect(0.7).tint(color(entry)) }
                                else { Image(systemName: symbol(entry)).foregroundColor(color(entry)).font(.system(size: 15, weight: .semibold)) }
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                                Text(entry.detail).font(.caption).foregroundColor(.secondary).lineLimit(2)
                                if let fraction = entry.fraction, entry.ended == nil { ProgressView(value: fraction).tint(color(entry)) }
                            }
                            Spacer(minLength: 6)
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(entry.state.rawValue).font(.caption2.weight(.semibold)).foregroundColor(color(entry))
                                Text(elapsed(entry, now: context.date)).font(.caption2.monospacedDigit()).foregroundColor(.secondary)
                            }
                        }
                        .padding(12)
                        .lrLiquidGlass(cornerRadius: 16)
                    }
                }
            }
        }
    }
    private func color(_ e: LongTaskCenter.Entry) -> Color {
        switch e.state { case .completed: return .green; case .failed: return .red; case .pausedByIOS: return .orange; case .backgroundGranted: return .indigo; case .running: return .blue }
    }
    private func symbol(_ e: LongTaskCenter.Entry) -> String {
        switch e.state { case .completed: return "checkmark"; case .failed: return "xmark"; case .pausedByIOS: return "pause.fill"; default: return "hourglass" }
    }
    private func elapsed(_ e: LongTaskCenter.Entry, now: Date) -> String {
        let seconds = Int((e.ended ?? now).timeIntervalSince(e.started))
        return seconds >= 3600 ? String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60) : String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

/// Live preview of the running desktop on Home. It shows the session's own
/// frames (no second X server, no fake animation), refreshes at most 5 times a
/// second and only while visible, and only when a new frame arrived.
struct DesktopPreviewCard: View {
    let phase: HomeStatus.Phase
    let stateText: String
    var open: () -> Void
    @State private var image: UIImage?
    @State private var generation: UInt64 = 0
    @State private var visible = false
    private let tick = Timer.publish(every: 0.2, on: .main, in: .common).autoconnect()
    var body: some View {
        Button(action: open) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(white: 0.06))
                if let image, phase != .off, phase != .stopped {
                    Image(uiImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .padding(6)
                } else if let last = image ?? DesktopPreviewCard.lastFrame {
                    // The last frame of your desktop, dimmed: what Open Desktop brings back.
                    Image(uiImage: last).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous)).padding(6)
                        .saturation(0.6).opacity(0.45)
                    caption
                } else {
                    MiniDesktopArt().clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous)).padding(6)
                    caption
                }
                if phase == .starting {
                    VStack { Spacer(); HStack(spacing: 8) { ProgressView().tint(.white); Text(stateText).font(.caption.weight(.medium)).foregroundColor(.white) }
                        .padding(.horizontal, 12).padding(.vertical, 7).background(Capsule().fill(.black.opacity(0.65))).padding(10) }
                }
            }
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 1))
        }
        .buttonStyle(HomeTileStyle())
        .accessibilityLabel(phase == .ready || phase == .degraded ? "Live desktop preview. Opens the desktop." : "Desktop. \(stateText)")
        .onAppear { visible = true; LRRuntimeBridge.setDesktopPreviewWanted(true); refresh() }
        .onDisappear { visible = false; LRRuntimeBridge.setDesktopPreviewWanted(false) }
        .onReceive(tick) { _ in if visible { refresh() } }
        .onChange(of: phase) { p in if p == .stopped || p == .off { if let image { DesktopPreviewCard.remember(image) }; image = nil; generation = 0 } else { LRRuntimeBridge.setDesktopPreviewWanted(visible) } }
    }
    private func refresh() {
        guard phase != .stopped, phase != .off else { return }
        var g = generation
        if let next = LRRuntimeBridge.desktopPreviewImageIfChanged(since: &g) { image = next; generation = g; DesktopPreviewCard.remember(next) }
    }
    // Last desktop frame, kept across launches (Caches; never synced or shared).
    private static let lastFrameURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("LinuxRunnerDesktopLastFrame.jpg")
    static var lastFrame: UIImage? = UIImage(contentsOfFile: lastFrameURL.path)
    private static var lastSaved = Date.distantPast
    static func remember(_ image: UIImage) {
        lastFrame = image
        guard Date().timeIntervalSince(lastSaved) > 10 else { return }
        lastSaved = Date()
        DispatchQueue.global(qos: .utility).async { try? image.jpegData(compressionQuality: 0.7)?.write(to: lastFrameURL, options: .atomic) }
    }
    private var caption: some View {
        VStack { Spacer(); HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(phase == .off ? "Linux is not running" : phase == .starting ? "Starting desktop…" : "Desktop stopped").font(.subheadline.weight(.semibold)).foregroundColor(.white)
                Text(phase == .off ? "Tap to start Linux" : "Tap to start your desktop").font(.caption).foregroundColor(.white.opacity(0.7))
            }
            Spacer()
        }.padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 30) }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

/// A drawn miniature desktop (wallpaper, two windows, a panel) for when no
/// frame of the user's desktop exists yet. Pure shapes: no images, no icons.
struct MiniDesktopArt: View {
    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            ZStack(alignment: .topLeading) {
                LinearGradient(colors: [Color(red: 0.07, green: 0.12, blue: 0.30), Color(red: 0.20, green: 0.10, blue: 0.38), Color(red: 0.05, green: 0.05, blue: 0.12)], startPoint: .topLeading, endPoint: .bottomTrailing)
                Circle().fill(Color(red: 0.35, green: 0.45, blue: 1.0).opacity(0.35)).frame(width: w * 0.7).blur(radius: 40).offset(x: w * 0.35, y: -h * 0.2)
                window(width: w * 0.46, height: h * 0.48).offset(x: w * 0.08, y: h * 0.12)
                window(width: w * 0.40, height: h * 0.42).offset(x: w * 0.46, y: h * 0.30)
                VStack { Spacer()
                    HStack(spacing: 6) {
                        Capsule().fill(Color.white.opacity(0.55)).frame(width: 22, height: 6)
                        ForEach(0..<3) { _ in RoundedRectangle(cornerRadius: 2).fill(Color.white.opacity(0.25)).frame(width: 14, height: 6) }
                        Spacer()
                        Capsule().fill(Color.white.opacity(0.35)).frame(width: 26, height: 6)
                    }.padding(.horizontal, 10).frame(height: max(14, h * 0.08)).background(Color.black.opacity(0.45))
                }
            }
        }
    }
    private func window(width: CGFloat, height: CGFloat) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) { ForEach(0..<3) { _ in Circle().fill(Color.white.opacity(0.35)).frame(width: 5, height: 5) }; Spacer() }
                .padding(.horizontal, 7).frame(height: 12).background(Color.white.opacity(0.14))
            Rectangle().fill(Color.white.opacity(0.07))
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(Color.white.opacity(0.12), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.35), radius: 8, y: 4)
    }
}

// MARK: - Distributions

/// Distributions L2iOS can actually install, in setup order.
struct CatalogDistribution: Identifiable {
    let id: String, name: String, summary: String, detail: String
    let experimental: Bool
    static let all: [CatalogDistribution] = [
        .init(id: "debian", name: "Debian 13", summary: "Recommended · APT", detail: "Stable, widest app support, all desktops", experimental: false),
        .init(id: "ubuntu", name: "Ubuntu 24.04", summary: "APT · Canonical", detail: "Official Ubuntu Base ARM64", experimental: true),
        .init(id: "arch", name: "Arch Linux ARM", summary: "Rolling · pacman", detail: "Rolling release, X11 & Wayland, KDE Plasma", experimental: false),
        .init(id: "fedora", name: "Fedora 44", summary: "DNF userspace", detail: "Lightweight desktop and KDE Plasma", experimental: false),
        .init(id: "opensuse", name: "openSUSE Tumbleweed", summary: "Rolling · zypper", detail: "Official openSUSE ARM64 rolling rootfs", experimental: true),
        .init(id: "rocky", name: "Rocky Linux 9", summary: "Enterprise · DNF", detail: "RHEL-compatible enterprise ARM64 rootfs", experimental: true),
        .init(id: "almalinux", name: "AlmaLinux 9", summary: "Enterprise · DNF", detail: "Community-owned RHEL-compatible ARM64", experimental: true),
        .init(id: "centos", name: "CentOS Stream 9", summary: "Rolling Enterprise · DNF", detail: "Upstream RHEL development branch ARM64", experimental: true),
        .init(id: "kubuntu", name: "Kubuntu 24.04", summary: "Ubuntu + KDE", detail: "Ubuntu Base with KDE Plasma", experimental: true),
        .init(id: "xubuntu", name: "Xubuntu 24.04", summary: "Ubuntu + Xfce", detail: "Ubuntu Base with lightweight Xfce", experimental: true),
        .init(id: "lubuntu", name: "Lubuntu 24.04", summary: "Ubuntu + LXQt", detail: "Ubuntu Base with fast LXQt desktop", experimental: true),
        .init(id: "pop", name: "Pop!_OS 24.04", summary: "System76 · APT", detail: "Ubuntu base with Pop!_OS repository", experimental: true),
        .init(id: "zorin", name: "Zorin OS 18", summary: "Windows-like · APT", detail: "Ubuntu base with Zorin OS look", experimental: true),
        .init(id: "kali", name: "Kali Linux", summary: "Security · APT", detail: "Kali Xfce desktop and security tool sets", experimental: false),
        .init(id: "void", name: "Void Linux", summary: "Independent · xbps", detail: "Independent rolling release; very light", experimental: true),
        .init(id: "devuan", name: "Devuan 5", summary: "Init-free · APT", detail: "Debian without systemd (Daedalus ARM64)", experimental: true),
        .init(id: "gentoo", name: "Gentoo Linux", summary: "Source · Portage", detail: "Gentoo ARM64 OpenRC stage rootfs", experimental: true),
        .init(id: "oracle", name: "Oracle Linux 9", summary: "Enterprise · DNF", detail: "Oracle Linux 9 ARM64 rootfs", experimental: true),
        .init(id: "alpine", name: "Alpine 3.24", summary: "Small · APK", detail: "Lightweight musl Linux for terminal", experimental: false),
        .init(id: "steamos", name: "SteamOS ARM64", summary: "Valve SteamFrame", detail: "Valve ARM64 recovery image (experimental)", experimental: true),
    ]
}

/// The distribution's own logo (DistroLogos.bundle, see its SOURCES.md) on a
/// light tile, or an iOS-style squircle badge for additional mainstream distros.
struct DistroBadge: View {
    let distributionID: String?
    var size: CGFloat = 46
    private static let cache = NSCache<NSString, UIImage>()
    private var file: String? {
        switch distributionID ?? "alpine" {
        case "debian": return "debian"
        case "arch", "archarm": return "arch"
        case "fedora": return "fedora"
        case "ubuntu", "kubuntu", "xubuntu", "lubuntu": return "ubuntu"
        case "kali": return "kali"
        case "steamos": return "steamos"
        case "pop": return "pop"
        case "zorin": return "zorin"
        case "void": return "void"
        case "opensuse", "opensuse-tumbleweed": return "opensuse"
        case "alpine": return "alpine"
        default: return nil
        }
    }
    private var customBadge: (String, [Color]) {
        switch distributionID ?? "" {
        case "rocky": return ("mountain.2.fill", [Color(red: 0.08, green: 0.72, blue: 0.48), Color(red: 0.04, green: 0.45, blue: 0.30)])
        case "almalinux": return ("star.circle.fill", [.blue, .indigo])
        case "centos": return ("square.grid.2x2.fill", [.purple, .indigo])
        case "devuan": return ("spiral", [.purple, .pink])
        case "gentoo": return ("sparkles", [.indigo, .purple])
        case "oracle": return ("circle.hexagongrid.fill", [.red, .orange])
        default: return ("shippingbox.fill", [.gray, .secondary])
        }
    }
    private var logo: UIImage? {
        guard let file else { return nil }
        if let image = Self.cache.object(forKey: file as NSString) { return image }
        guard let bundle = Bundle.main.url(forResource: "DistroLogos", withExtension: "bundle"),
              let image = UIImage(contentsOfFile: bundle.appendingPathComponent(file + ".png").path) else { return nil }
        Self.cache.setObject(image, forKey: file as NSString)
        return image
    }
    var body: some View {
        if let logo {
            RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                .fill(Color(white: 0.96))
                .frame(width: size, height: size)
                .overlay {
                    Image(uiImage: logo).resizable().interpolation(.high).scaledToFit().padding(size * 0.14)
                }
                .accessibilityHidden(true)
        } else {
            LRIOSIcon(symbol: customBadge.0, colors: customBadge.1, size: size)
                .accessibilityHidden(true)
        }
    }
}

/// A desktop environment's mark, in the same rounded tile as DistroBadge:
/// the icon theme's logo where one exists (DesktopLogos.bundle/SOURCES.md),
/// otherwise a symbol tile drawn by the app.
struct DesktopBadge: View {
    let desktopID: String
    var size: CGFloat = 46
    private static let cache = NSCache<NSString, UIImage>()
    private var logo: UIImage? {
        guard ["linuxrunner", "gnome", "plasma", "lxqt", "xfce"].contains(desktopID) else { return nil }
        if let image = Self.cache.object(forKey: desktopID as NSString) { return image }
        guard let bundle = Bundle.main.url(forResource: "DesktopLogos", withExtension: "bundle"),
              let image = UIImage(contentsOfFile: bundle.appendingPathComponent(desktopID + ".png").path) else { return nil }
        Self.cache.setObject(image, forKey: desktopID as NSString)
        return image
    }
    private var tile: (symbol: String, colors: [Color]) {
        switch desktopID {
        case "i3": return ("square.grid.2x2.fill", [Color(red: 0.20, green: 0.24, blue: 0.30), Color(red: 0.36, green: 0.44, blue: 0.54)])
        case "sway": return ("rectangle.split.2x2.fill", [Color(red: 0.15, green: 0.55, blue: 0.65), Color(red: 0.12, green: 0.35, blue: 0.55)])
        case "fluxbox": return ("square.stack.3d.up.fill", [Color(red: 0.35, green: 0.35, blue: 0.45), Color(red: 0.55, green: 0.45, blue: 0.65)])
        case "icewm": return ("snowflake", [Color(red: 0.22, green: 0.55, blue: 0.90), Color(red: 0.45, green: 0.78, blue: 0.98)])
        case "wayfire": return ("flame.fill", [Color(red: 1.00, green: 0.58, blue: 0.20), Color(red: 0.90, green: 0.25, blue: 0.20)])
        case "hyprland": return ("square.grid.3x2.fill", [Color(red: 0.20, green: 0.80, blue: 0.90), Color(red: 0.25, green: 0.40, blue: 0.95)])
        case "enlightenment": return ("sparkles", [Color(red: 0.62, green: 0.36, blue: 0.95), Color(red: 0.95, green: 0.35, blue: 0.62)])
        case "mate": return ("leaf.fill", [Color(red: 0.45, green: 0.75, blue: 0.30), Color(red: 0.20, green: 0.55, blue: 0.25)])
        case "cinnamon": return ("circle.grid.cross.fill", [Color(red: 0.85, green: 0.55, blue: 0.30), Color(red: 0.60, green: 0.35, blue: 0.20)])
        case "cosmic": return ("sparkle", [Color(red: 0.28, green: 0.75, blue: 0.85), Color(red: 0.55, green: 0.40, blue: 0.95)])
        case "budgie": return ("circle.hexagongrid.fill", [Color(red: 0.30, green: 0.60, blue: 0.95), Color(red: 0.55, green: 0.35, blue: 0.85)])
        default: return ("macwindow.on.rectangle", [Color(red: 0.25, green: 0.50, blue: 1.00), Color(red: 0.36, green: 0.30, blue: 0.90)])
        }
    }
    var body: some View {
        Group {
            if let logo, desktopID == "linuxrunner" {
                // The app's own icon: full-bleed, like on the Home Screen.
                Image(uiImage: logo).resizable().interpolation(.high).scaledToFill()
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
            } else if let logo {
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous).fill(Color(white: 0.96))
                    .overlay(Image(uiImage: logo).resizable().interpolation(.high).scaledToFit().padding(size * 0.12))
            } else {
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .fill(LinearGradient(colors: tile.colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(Image(systemName: tile.symbol).font(.system(size: size * 0.42, weight: .semibold)).foregroundColor(.white))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// One desktop in the picker: mark, name, badges, what it is, and its state
/// (selected, ready to use, install, or installing with live progress).
struct DesktopChoiceCard: View {
    let option: DesktopOption
    let distro: String
    let selected: Bool
    let installed: Bool
    let progress: String?
    let enabled: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 14) {
                DesktopBadge(desktopID: option.id, size: 52)
                VStack(alignment: .leading, spacing: 5) {
                    Text(option.title).font(.headline).foregroundColor(.primary).lineLimit(1).minimumScaleFactor(0.8)
                    if !option.badges(distro).isEmpty {
                        HStack(spacing: 6) {
                            ForEach(option.badges(distro), id: \.self) { badge in
                                StatusChip(text: badge, color: badge == "Recommended" ? .accentColor : badge == "Experimental" ? .orange : .green)
                                    .fixedSize()
                            }
                        }
                    }
                    Text(option.detail).font(.footnote).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                    if let progress {
                        HStack(spacing: 6) { ProgressView().scaleEffect(0.7); Text(progress).font(.caption).foregroundColor(.secondary).lineLimit(2) }
                    } else if !installed {
                        Label("Install", systemImage: "arrow.down.circle.fill").font(.caption.weight(.semibold)).foregroundColor(.accentColor)
                    }
                }
                Spacer(minLength: 4)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title2).foregroundColor(selected ? .accentColor : Color(.tertiaryLabel))
            }
            .padding(14)
            .lrLiquidGlass(cornerRadius: 18, interactive: true, tint: selected ? .accentColor : nil)
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2))
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled || selected ? 1 : 0.55)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityHint(installed ? "Selects this desktop" : "Installs this desktop")
    }
}

struct StatusChip: View {
    let text: String; let color: Color
    var body: some View {
        Text(text).font(.caption2.weight(.semibold)).foregroundColor(color)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .lrLiquidGlassCapsule(tint: color)
    }
}

struct InstalledDistributionCard: View {
    let name: String, distributionID: String?, version: String, size: String, desktop: String?
    let active: Bool, nextLaunch: Bool
    var body: some View {
        HStack(spacing: 14) {
            DistroBadge(distributionID: distributionID)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(name).font(.headline).foregroundColor(.primary).lineLimit(1)
                    if active { StatusChip(text: "Active", color: .green) }
                    else if nextLaunch { StatusChip(text: "Next launch", color: .accentColor) }
                }
                Text([version, size].filter { !$0.isEmpty }.joined(separator: " · ")).font(.caption).foregroundColor(.secondary).lineLimit(1)
                if let desktop { Label(desktop, systemImage: "macwindow").font(.caption).foregroundColor(.secondary).lineLimit(1) }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundColor(.secondary.opacity(0.6))
        }
        .padding(14)
        .lrLiquidGlass(cornerRadius: 18, interactive: true, tint: active ? .green : nil)
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(active ? Color.green.opacity(0.55) : Color.clear, lineWidth: 1.5))
        .accessibilityElement(children: .combine)
    }
}

struct CatalogDistributionCard: View {
    let item: CatalogDistribution
    let installed: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                DistroBadge(distributionID: item.id, size: 38)
                Spacer()
                if item.experimental { StatusChip(text: "Experimental", color: .orange) }
            }
            Text(item.name).font(.subheadline.weight(.semibold)).foregroundColor(.primary)
            Text(item.summary).font(.caption).foregroundColor(.secondary)
            Text(item.detail).font(.caption2).foregroundColor(.secondary).lineLimit(3).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Label(installed ? "Add Another" : "Install", systemImage: installed ? "plus" : "arrow.down.circle")
                .font(.caption.weight(.semibold)).foregroundColor(.accentColor)
        }
        .padding(14).frame(maxWidth: .infinity, minHeight: 168, alignment: .topLeading)
        .lrLiquidGlass(cornerRadius: 18, interactive: true)
        .accessibilityElement(children: .combine)
    }
}

/// Distinct L2iOS Home hero dashboard card with integrated Desktop + Terminal actions.
struct L2iOSHeroDeck: View {
    let distroName: String
    let distributionID: String?
    let running: Bool
    let starting: Bool
    let desktopAlive: Bool
    let desktopStarting: Bool
    let statusText: String
    let canStart: Bool
    let onPrimary: () -> Void
    let onTerminal: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                DistroBadge(distributionID: distributionID, size: 52)
                VStack(alignment: .leading, spacing: 3) {
                    Text(distroName)
                        .font(.title3.weight(.bold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    Text(running ? (desktopAlive ? "Desktop session active · ARM64" : desktopStarting ? "Starting graphical session…" : "Linux runtime online · ARM64") : "Standby · Tap Boot to start")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Circle()
                    .fill(running ? (desktopAlive ? Color.green : Color.cyan) : Color.secondary.opacity(0.4))
                    .frame(width: 10, height: 10)
                    .shadow(color: running ? (desktopAlive ? Color.green.opacity(0.7) : Color.cyan.opacity(0.7)) : .clear, radius: 6)
            }

            HStack(spacing: 10) {
                Button(action: onPrimary) {
                    HStack(spacing: 8) {
                        if starting {
                            ProgressView().tint(.white).scaleEffect(0.85)
                        } else {
                            Image(systemName: running ? (desktopAlive ? "sparkles.tv.fill" : "play.fill") : "bolt.fill")
                                .font(.subheadline.weight(.semibold))
                        }
                        Text(running ? (desktopAlive ? "Resume Desktop" : "Open Desktop") : starting ? "Booting…" : "Boot Linux")
                            .font(.subheadline.weight(.bold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(LinearGradient(colors: running ? [Color.blue, Color.indigo] : [Color.teal, Color.blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                    )
                    .lrLiquidGlass(cornerRadius: 16, interactive: true, tint: running ? .blue : .teal)
                }
                .buttonStyle(HomeTileStyle())
                .disabled(running ? false : (starting || !canStart))

                if let onTerminal {
                    Button(action: onTerminal) {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.left.forwardslash.chevron.right")
                                .font(.subheadline.weight(.bold))
                            Text("Shell")
                                .font(.subheadline.weight(.semibold))
                        }
                        .foregroundColor(.primary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 13)
                        .lrLiquidGlass(cornerRadius: 16, interactive: true)
                    }
                    .buttonStyle(HomeTileStyle())
                }
            }

            if !running && !starting && !statusText.isEmpty {
                Text(statusText)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(18)
        .lrLiquidGlass(cornerRadius: 24, tint: running ? .blue : nil)
    }
}

/// Sleek bento widget card with iOS squircle icon, title, and subtitle.
struct L2iOSBentoTile: View {
    let title: String
    let subtitle: String
    let symbol: String
    let colors: [Color]
    var badge: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                LRIOSIcon(symbol: symbol, colors: colors, size: 42, badge: badge)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.bold))
                    .foregroundColor(.secondary.opacity(0.6))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .lrLiquidGlass(cornerRadius: 20, interactive: true)
    }
}

/// Settings row label: an iOS-style squircle icon tile and a title.
struct SettingsLabel: View {
    let title: String, symbol: String, color: Color
    init(_ title: String, _ symbol: String, _ color: Color) { self.title = title; self.symbol = symbol; self.color = color }
    var body: some View {
        Label {
            Text(title)
        } icon: {
            LRIOSIcon(symbol: symbol, colors: [color.opacity(0.82), color], size: 30)
        }
    }
}

// MARK: - CPU & Memory (Settings › Graphics & Performance)

/// What Linux programs are told about CPU cores and memory. Programs size their
/// worker threads (make -j, Blender, browsers, Java) and heaps from these, and
/// guest threads run on separate CPU cores. Applied at the next launch.
struct SystemResourcesView: View {
    @AppStorage(LRSystemCPUCoresKey) private var cores = 0
    @AppStorage(LRSystemMemoryMBKey) private var memoryMB = 0
    @AppStorage("LinuxRunnerSystem.unlockHighRAM") private var unlockHighRAM = false
    private let hostCores = max(1, min(16, ProcessInfo.processInfo.activeProcessorCount))
    /// Advertised RAM tier: iOS reports a little less than the marketed amount
    /// (a 12 GB iPhone can report under 11.5 GiB), so classify instead of rounding.
    private let deviceGB: Int = {
        let gib = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824
        switch gib {
        case 14...: return 16
        case 10...: return 12
        case 7...: return 8
        case 5...: return 6
        case 3.5...: return 4
        default: return max(1, Int(gib.rounded()))
        }
    }()
    private let appliedCores = ProcessInfo.processInfo.environment["LINUXRUNNER_CPU_CORES"].flatMap(Int.init) ?? 0
    private let appliedMemoryMB = ProcessInfo.processInfo.environment["LINUXRUNNER_MEMORY_MB"].flatMap(Int.init) ?? 0

    /// Standard cap keeps headroom for iOS; Extended RAM Tiers unlocks up to deviceGB - 1 (max 16 GB).
    private var maximumGB: Int {
        if unlockHighRAM {
            return min(16, max(2, deviceGB - 1))
        }
        let limit = deviceGB >= 12 ? deviceGB - 3 : deviceGB >= 8 ? deviceGB - 2 : deviceGB >= 6 ? 4 : max(1, deviceGB / 2)
        return min(12, max(1, limit))
    }

    private var memoryOptionsMB: [Int] {
        let maxMB = maximumGB * 1024
        let presets = [0, 512, 1024, 1536, 2048, 3072, 4096, 6144, 8192, 10240, 12288, 16384]
        return presets.filter { $0 <= maxMB }
    }

    private func formatRAM(_ mb: Int) -> String {
        if mb == 0 { return "Auto" }
        if mb < 1024 { return "\(mb) MB" }
        if mb % 1024 == 0 { return "\(mb / 1024) GB" }
        return String(format: "%.1f GB", Double(mb) / 1024.0)
    }

    /// What iOS lets L2iOS use right now (footprint plus what is still
    /// available); nil where iOS reports no app limit (Simulator, Mac).
    private var iosAllowanceGB: Double? {
        let available = os_proc_available_memory()
        guard available > 0 else { return nil }
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let footprint = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
        } == KERN_SUCCESS ? Double(info.phys_footprint) : 0
        return (footprint + Double(available)) / 1_073_741_824
    }
    private var pendingRestart: Bool { cores != appliedCores || memoryMB != appliedMemoryMB }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header
                card(title: "CPU Cores", symbol: "cpu.fill", colors: [.indigo, .purple],
                     value: cores == 0 ? "Automatic · 4" : "\(cores) of \(hostCores)",
                     detail: "Linux programs start this many worker threads, and each runs on its own core. More cores speed up compiling, rendering and browsers; Automatic keeps 4, which suits most apps.") {
                    chips(options: [0] + Array(1...hostCores), selection: $cores) { $0 == 0 ? "Auto" : "\($0)" }
                }
                card(title: "Linux Memory", symbol: "memorychip.fill", colors: [.teal, .blue],
                     value: memoryMB == 0 ? "Automatic" : formatRAM(memoryMB),
                     detail: "The memory Linux programs see. Java, browsers, IDEs and games size their heaps from it. Up to \(maximumGB) GB on this \(deviceGB) GB device.") {
                    chips(options: memoryOptionsMB, selection: $memoryMB) { formatRAM($0) }
                    Toggle("Extended RAM Tiers", isOn: $unlockHighRAM)
                        .font(.subheadline)
                        .padding(.top, 4)
                    if memoryMB > 0, let allowance = iosAllowanceGB, Double(memoryMB) / 1024 > allowance {
                        Label(String(format: "iOS currently allows L2iOS about %.1f GB. Programs that use more than that can be closed by iOS unless using increased-memory entitlements.", allowance), systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote).foregroundStyle(.orange).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                if pendingRestart {
                    Label("Applies the next time L2iOS starts. Close it from the app switcher and open it again.", systemImage: "arrow.clockwise.circle.fill")
                        .font(.footnote.weight(.medium)).foregroundStyle(.blue)
                        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                        .lrLiquidGlass(cornerRadius: 16, tint: .blue)
                }
            }
            .padding(.horizontal, 20).padding(.vertical, 12).padding(.bottom, 96)
        }
        .background(LRAmbientGlassBackdrop())
        .navigationTitle("CPU & Memory")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(LinearGradient(colors: [.indigo, .teal], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 54, height: 54)
                .overlay(Image(systemName: "speedometer").font(.system(size: 24, weight: .semibold)).foregroundColor(.white))
            VStack(alignment: .leading, spacing: 3) {
                Text(UIDevice.current.model).font(.headline)
                Text("\(hostCores) CPU cores · \(deviceGB) GB memory").font(.subheadline).foregroundStyle(.secondary)
                if let allowance = iosAllowanceGB {
                    Text(String(format: "iOS allows L2iOS about %.1f GB now", allowance)).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .lrLiquidGlass(cornerRadius: 20)
    }

    private func card<Content: View>(title: String, symbol: String, colors: [Color], value: String, detail: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 34, height: 34)
                    .overlay(Image(systemName: symbol).font(.system(size: 16, weight: .semibold)).foregroundColor(.white))
                Text(title).font(.headline)
                Spacer()
                Text(value).font(.subheadline.weight(.semibold).monospacedDigit()).foregroundStyle(.secondary)
            }
            content()
            Text(detail).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .lrLiquidGlass(cornerRadius: 20)
    }

    private func chips(options: [Int], selection: Binding<Int>, label: @escaping (Int) -> String) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: 8)], spacing: 8) {
            ForEach(options, id: \.self) { option in
                let selected = selection.wrappedValue == option
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { selection.wrappedValue = option }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Text(label(option))
                        .font(.subheadline.weight(selected ? .semibold : .regular).monospacedDigit())
                        .frame(maxWidth: .infinity, minHeight: 38)
                        .foregroundColor(selected ? .white : .primary)
                        .background(Capsule().fill(selected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.primary.opacity(0.08))))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }
}

// MARK: - Shared settings design (GPU, Devices, File Sharing)
// Cards in the style of CPU & Memory: gradient icon tile, headline, short
// value, content, and long explanations folded into "More info".
struct LRIconTile: View {
    let symbol: String; let colors: [Color]; var size: CGFloat = 34
    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
            .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: size, height: size)
            .overlay(Image(systemName: symbol).font(.system(size: size * 0.47, weight: .semibold)).foregroundColor(.white))
    }
}
struct LRCard<Content: View>: View {
    let title: String; let symbol: String; let colors: [Color]; var value: String? = nil
    @ViewBuilder let content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                LRIconTile(symbol: symbol, colors: colors)
                Text(title).font(.headline)
                Spacer()
                if let value { Text(value).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary).lineLimit(1) }
            }
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .lrLiquidGlass(cornerRadius: 20)
    }
}
struct LRChoice: Identifiable { let id: String; let title: String; let subtitle: String; let symbol: String }
struct LRChoiceList: View {
    let choices: [LRChoice]; @Binding var selection: String
    var body: some View {
        VStack(spacing: 8) {
            ForEach(choices) { choice in
                let selected = selection == choice.id
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { selection = choice.id }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: choice.symbol).font(.system(size: 16, weight: .semibold))
                            .foregroundColor(selected ? .white : .accentColor)
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(selected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.accentColor.opacity(0.14))))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(choice.title).font(.subheadline.weight(.semibold)).foregroundColor(.primary)
                            Text(choice.subtitle).font(.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 4)
                        Image(systemName: selected ? "checkmark.circle.fill" : "circle").font(.title3)
                            .foregroundColor(selected ? .accentColor : Color(.tertiaryLabel))
                    }
                    .padding(10)
                    .lrLiquidGlass(cornerRadius: 14, interactive: true, tint: selected ? .accentColor : nil)
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(selected ? Color.accentColor.opacity(0.6) : .clear, lineWidth: 1.5))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }
}
struct LRStatusPill: View {
    let text: String; let color: Color
    var body: some View {
        Text(text).font(.caption2.weight(.semibold)).lineLimit(1)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .foregroundColor(color)
            .lrLiquidGlassCapsule(tint: color)
    }
}
struct LRMoreInfo<Content: View>: View {
    var title = "More info"
    @ViewBuilder let content: () -> Content
    @State private var open = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { withAnimation(.easeOut(duration: 0.2)) { open.toggle() } } label: {
                HStack(spacing: 4) {
                    Text(title).font(.footnote.weight(.semibold))
                    Image(systemName: "chevron.down").font(.caption2.weight(.bold)).rotationEffect(.degrees(open ? 180 : 0))
                }.foregroundColor(.accentColor)
            }.buttonStyle(.plain)
            if open { content().font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
        }
    }
}
struct LRNavRow: View {
    let title: String; let subtitle: String?; let symbol: String; let colors: [Color]
    var body: some View {
        HStack(spacing: 12) {
            LRIconTile(symbol: symbol, colors: colors, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundColor(.primary)
                if let subtitle { Text(subtitle).font(.caption).foregroundColor(.secondary).lineLimit(1) }
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundColor(Color(.tertiaryLabel))
        }
        .padding(.vertical, 4).contentShape(Rectangle())
    }
}
