import SwiftUI
import UniformTypeIdentifiers

// Guided setup: Welcome → Distribution → Install Linux → (restart into it) →
// Account → Desktop → Finish → Open Desktop. Uses the verified installers, the
// native account setup (password hashed in the app; tools installed if absent)
// and the same desktop-profile repair as Open Desktop. It opens by itself only
// when no Linux environment exists; existing environments, homes and accounts
// are never modified, and an existing account can be used as it is.
enum SetupStep: String { case welcome, distribution, install, relaunch, account, desktop, done }

struct SetupWizardView: View {
    @ObservedObject var manager: EnvironmentManager
    var openDesktop: () -> Void
    @Environment(\.dismiss) private var dismiss
    @AppStorage("LinuxRunnerSetup.step") private var stepRaw = SetupStep.welcome.rawValue
    @AppStorage("LinuxRunnerSetup.distribution") private var distribution = "debian"
    @AppStorage("LinuxRunnerSetup.root") private var setupRoot = ""
    @StateObject private var debian = DebianInstaller()
    @StateObject private var arch = ArchInstaller()
    @StateObject private var fedora = FedoraInstaller()
    @StateObject private var kali = KaliInstaller()
    @StateObject private var ubuntu = UbuntuInstaller()
    @StateObject private var voidInstaller = VoidInstaller()
    @StateObject private var steamos = SteamOSInstaller()
    @StateObject private var mainstream = MainstreamDistroInstaller()
    @State private var steamOSImporter = false
    @State private var customRootfsImporter = false
    @State private var username = ""
    @State private var password = ""
    @State private var confirmation = ""
    @State private var administrator = true
    @State private var working: String?
    @State private var problem: String?
    @State private var desktopReady = false
    @State private var extraDesktops: Set<String> = []
    @State private var chosenDesktop = "linuxrunner"
    private var step: SetupStep { SetupStep(rawValue: stepRaw) ?? .welcome }
    private var anyInstalling: Bool {
        working != nil || debian.running || arch.running || fedora.running || kali.running || ubuntu.running || voidInstaller.running || steamos.running || mainstream.running || manager.busy
    }

    var body: some View {
        NavigationView {
            Form { content }
                .navigationTitle(title)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(step == .done ? "Close" : "Later") { dismiss() }.disabled(anyInstalling) } }
        }
        .navigationViewStyle(.stack)
        .overlay(alignment: .bottom) { InstallProgressCard() }
        .interactiveDismissDisabled(anyInstalling)
        .onAppear(perform: resume)
        .fileImporter(isPresented: $steamOSImporter, allowedContentTypes: [.data], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls): if let source = urls.first { installSteamOS(from: source) }
            case .failure(let error): problem = error.localizedDescription
            }
        }
        .fileImporter(isPresented: $customRootfsImporter, allowedContentTypes: [.data, .archive], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                if let source = urls.first {
                    mainstream.importLocalArchive(url: source) { environment in
                        manager.acceptInstalled(environment)
                        setupRoot = environment.rootfsName
                        LRRuntimeBridge.setNextRootName(environment.rootfsName)
                        stepRaw = (LRRuntimeBridge.isRunning() && LRRuntimeBridge.activeRootName() == environment.rootfsName) ? SetupStep.account.rawValue : SetupStep.relaunch.rawValue
                    }
                }
            case .failure(let error): problem = error.localizedDescription
            }
        }
    }

    private var title: String {
        switch step {
        case .welcome: return "Welcome"; case .distribution: return "Choose Linux"; case .install: return "Install Linux"
        case .relaunch: return "Restart L2iOS"; case .account: return "Your Account"; case .desktop: return "Desktop"; case .done: return "Ready"
        }
    }

    @ViewBuilder private var content: some View {
        switch step {
        case .welcome:
            Section { Text("L2iOS runs real ARM64 Linux programs on this iPhone with its own interpreter — no virtual machine.")
                Text("Setup installs Linux, creates your account and prepares the graphical desktop. Everything can be changed later in Settings.").foregroundStyle(.secondary) }
            if !manager.environments.isEmpty { Section { Text("Configure an existing environment or install another distribution. Your files and accounts are preserved.").font(.footnote) } }
            Section { Button("Continue") { stepRaw = SetupStep.distribution.rawValue } }
        case .distribution:
            Section(footer: Text("Debian is recommended. Ubuntu, Fedora, Arch, Kali, openSUSE, Rocky, AlmaLinux, CentOS, Devuan, Gentoo, Oracle, Void, Alpine, and SteamOS are supported on ARM64.")) {
                Picker("Distribution", selection: $distribution) {
                    Text("Debian GNU/Linux 13 (ARM64) — recommended").tag("debian")
                    Text("Ubuntu \(UbuntuImage.version) (ARM64)").tag("ubuntu")
                    Text("Arch Linux ARM (ARM64)").tag("arch")
                    Text("Fedora Linux 44 (ARM64)").tag("fedora")
                    Text("openSUSE Tumbleweed (ARM64)").tag("opensuse")
                    Text("Rocky Linux 9 (ARM64)").tag("rocky")
                    Text("AlmaLinux 9 (ARM64)").tag("almalinux")
                    Text("CentOS Stream 9 (ARM64)").tag("centos")
                    Text("Kubuntu 24.04 (ARM64)").tag("kubuntu")
                    Text("Xubuntu 24.04 (ARM64)").tag("xubuntu")
                    Text("Lubuntu 24.04 (ARM64)").tag("lubuntu")
                    Text("Pop!_OS 24.04 (ARM64)").tag("pop")
                    Text("Zorin OS 18 (ARM64)").tag("zorin")
                    Text("Kali Linux \(KaliImage.version) (ARM64)").tag("kali")
                    Text("Void Linux (ARM64)").tag("void")
                    Text("Devuan 5 Daedalus (ARM64)").tag("devuan")
                    Text("Gentoo Linux (ARM64)").tag("gentoo")
                    Text("Oracle Linux 9 (ARM64)").tag("oracle")
                    Text("Alpine Linux 3.24 (ARM64)").tag("alpine")
                    Text("SteamOS ARM64").tag("steamos")
                }.pickerStyle(.inline).labelsHidden()
            }
            let installed = manager.environments.filter { ($0.distributionID ?? "alpine") == distribution }
            if !installed.isEmpty {
                Section("Already Installed") {
                    ForEach(installed) { environment in
                        Button("Configure " + environment.name) { configureExisting(environment) }
                    }
                    Text("Uses the existing environment, accounts and files. Switching environments takes effect after relaunch.").font(.footnote).foregroundStyle(.secondary)
                }
            }
            Section { Button(installed.isEmpty ? "Continue" : "Install Another Environment") { stepRaw = SetupStep.install.rawValue } }
        case .install: install
        case .relaunch:
            Section { Text("Linux is installed and selected. Close L2iOS completely (swipe it away in the app switcher) and open it again — setup continues with your account.") }
            Section { Text("iOS allows one Linux runtime per app launch, so this restart is needed once.").font(.footnote).foregroundStyle(.secondary) }
        case .account: account
        case .desktop: desktop
        case .done:
            Section { Label("Linux is ready", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                Text("Add applications any time from the App Store tab.").font(.footnote).foregroundStyle(.secondary) }
            Section { Button { stepRaw = SetupStep.welcome.rawValue; setupRoot = ""; dismiss(); openDesktop() } label: { Label("Open Desktop", systemImage: "desktopcomputer").font(.headline) }.disabled(!LRRuntimeBridge.isRunning()) }
        }
        if let working { Section { HStack(spacing: 12) { ProgressView(); Text(working) } } }
        if let problem { Section { Text(problem).foregroundStyle(.red) } }
    }

    @ViewBuilder private var install: some View {
        let free = (try? LRRuntimeBridge.managedStorageURL().resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage) ?? 0
        let manifest = try? DebianManifest.load()
        let steamManifest = try? SteamOSManifest.load()
        let alpineBytes = Int64((try? Bundle.main.url(forResource: "root", withExtension: "tar.gz")?.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        let ubuntuFlavors = ["ubuntu", "pop", "zorin", "kubuntu", "xubuntu", "lubuntu"]
        let download = distribution == "debian" ? (manifest?.downloadBytes ?? 0) : distribution == "fedora" ? FedoraImage.bytes : distribution == "kali" ? KaliImage.bytes : ubuntuFlavors.contains(distribution) ? UbuntuImage.bytes : distribution == "void" ? VoidImage.bytes : 0
        let installed = distribution == "debian" ? (manifest?.installedBytes ?? 0) : alpineBytes * 3
        Section("Storage") {
            row("Download", distribution == "steamos" ? (steamManifest.flatMap { SteamOSInstaller.downloadedImage($0) } != nil ? "Already downloaded" : ByteCountFormatter.string(fromByteCount: steamManifest?.source?.bytes ?? 0, countStyle: .file) + " from Valve") : distribution == "arch" ? "Calculated from the signed package selection" : MainstreamDistroSpec.spec(for: distribution) != nil ? "Fetched from official ARM64 mirror" : (["debian", "fedora", "kali", "void"] + ubuntuFlavors).contains(distribution) ? ByteCountFormatter.string(fromByteCount: download, countStyle: .file) : "None (included in the app)")
            row(distribution == "debian" || distribution == "steamos" ? "Installed size" : "Installed size (estimate)", distribution == "steamos" ? ByteCountFormatter.string(fromByteCount: steamManifest?.installedBytes ?? 0, countStyle: .file) : distribution == "arch" ? "At least 1.5 GB free for base installation" : distribution == "void" ? "At least 1.5 GB free for base installation" : (distribution == "fedora" || ubuntuFlavors.contains(distribution) || MainstreamDistroSpec.spec(for: distribution) != nil) ? "At least 2 GB free for base installation" : distribution == "kali" ? "About 0.9 GB base; desktop about 2 GB more; standard tools about 6 GB more" : ByteCountFormatter.string(fromByteCount: installed, countStyle: .file))
            row("Available", ByteCountFormatter.string(fromByteCount: free, countStyle: .file))
        }
        if distribution == "debian" {
            Section {
                if debian.running { Text(debian.message); ProgressView(value: debian.fraction); Button("Cancel", role: .destructive) { debian.cancel() } }
                else { Button("Install Debian") { startInstall() }.disabled(free < max(Int64(1 << 30), download + installed)) }
                if let failure = debian.failure { Text(failure).foregroundStyle(.red); Button("Try Again") { startInstall() } }
            } footer: { Text("Official Debian packages, checked against Debian's signed index. The desktop, sound and account tools are added in the next steps.") }
        } else if distribution == "arch" {
            Section {
                if arch.running { Text(arch.message); ProgressView(value: arch.fraction); Button("Cancel", role: .destructive) { arch.cancel() } }
                else { Button("Install Arch Linux ARM") { startInstall() }.disabled(free < Int64(1_500_000_000)) }
                if let failure = arch.failure { Text(failure).foregroundStyle(.red); Button("Try Again") { startInstall() } }
            } footer: { Text("Official signed Arch Linux ARM packages. Verified downloads are kept for retry. First-start configuration finishes before desktop packages are installed.") }
        } else if distribution == "fedora" {
            Section {
                if fedora.running { Text(fedora.message); ProgressView(value: fedora.fraction); Button("Cancel", role: .destructive) { fedora.cancel() } }
                else { Button("Install Fedora Linux") { startInstall() }.disabled(free < Int64(2_000_000_000)) }
                if let failure = fedora.failure { Text(failure).foregroundStyle(.red); Button("Try Again") { startInstall() } }
            } footer: { Text("Authenticates Fedora's official AArch64 WSL userspace image; runs it with L2iOS, without WSL, a Linux kernel or systemd. The lightweight GTK/X11 desktop and experimental KDE Plasma are available. Fedora sound is not yet qualified.") }
        } else if distribution == "kali" {
            Section {
                if kali.running { Text(kali.message); ProgressView(value: kali.fraction); Button("Cancel", role: .destructive) { kali.cancel() } }
                else { Button("Install Kali Linux") { startInstall() }.disabled(free < Int64(2_000_000_000)) }
                if let failure = kali.failure { Text(failure).foregroundStyle(.red); Button("Try Again") { startInstall() } }
            } footer: { Text("Kali's official ARM64 root filesystem (\(KaliImage.version)), checked against its published SHA-256; packages come from Kali's signed archive. The image's preset root and kali passwords are locked at first start; you create your own account next. Runs with L2iOS, without a Linux kernel or systemd.") }
        } else if ubuntuFlavors.contains(distribution) {
            let flavor = UbuntuFlavor(rawValue: distribution)
            Section {
                if ubuntu.running { Text(ubuntu.message); ProgressView(value: ubuntu.fraction); Button("Cancel", role: .destructive) { ubuntu.cancel() } }
                else { Button("Install \(flavor?.name ?? "Ubuntu")") { startInstall() }.disabled(free < Int64(2_000_000_000)) }
                if let failure = ubuntu.failure { Text(failure).foregroundStyle(.red); Button("Try Again") { startInstall() } }
            } footer: { Text(flavor.map { "\($0.name) \($0.version) is Ubuntu 24.04 with \($0.vendor) on top. L2iOS installs Canonical's official Ubuntu Base ARM64 (verified against its signed checksum), then adds \($0.vendor) during desktop setup." } ?? "Official Ubuntu Base ARM64, verified against Canonical's signed checksum.") }
        } else if distribution == "void" {
            Section {
                if voidInstaller.running { Text(voidInstaller.message); ProgressView(value: voidInstaller.fraction); Button("Cancel", role: .destructive) { voidInstaller.cancel() } }
                else { Button("Install Void Linux") { startInstall() }.disabled(free < Int64(1_500_000_000)) }
                if let failure = voidInstaller.failure { Text(failure).foregroundStyle(.red); Button("Try Again") { startInstall() } }
            } footer: { Text("Void Linux's official ARM64 ROOTFS (\(VoidImage.version)), checked against Void's signed checksum; packages come from Void's signed xbps repositories.") }
        } else if let spec = MainstreamDistroSpec.spec(for: distribution) {
            Section {
                if mainstream.running {
                    Text(mainstream.message)
                    ProgressView(value: mainstream.fraction)
                    Button("Cancel", role: .destructive) { mainstream.cancel() }
                } else {
                    Button("Install \(spec.displayName)") { startInstall() }.disabled(free < Int64(1_500_000_000))
                }
                if let failure = mainstream.failure { Text(failure).foregroundStyle(.red); Button("Try Again") { startInstall() } }
            } footer: { Text("Downloads the latest official \(spec.displayName) ARM64 rootfs from Linux Containers (images.linuxcontainers.org), verifies its published SHA-256 checksum, and imports it into an isolated environment.") }
        } else if distribution == "steamos" {
            Section {
                Text(steamos.message)
                if steamos.running {
                    ProgressView(value: steamos.fraction)
                    Button("Cancel Installation", role: .destructive) { steamos.cancel() }
                } else {
                    let required = steamManifest?.directRequiredFreeBytes(imagePresent: steamManifest.flatMap { SteamOSInstaller.downloadedImage($0) } != nil) ?? .max
                    Button(steamos.failure == nil ? "Install SteamOS" : "Try Again") { installSteamOSFromValve() }
                        .disabled(steamManifest?.supportsDirectInstall != true || free < required)
                    if free < required, required != .max {
                        Text("Needs " + ByteCountFormatter.string(fromByteCount: required, countStyle: .file) + " free while installing; about " + ByteCountFormatter.string(fromByteCount: steamManifest?.streamInstalledBytes ?? 0, countStyle: .file) + " stays in use afterwards.").foregroundStyle(.secondary)
                    }
                    if FileManager.default.fileExists(atPath: SteamOSInstaller.preparedArchiveURL.path) {
                        Button("Install Prepared SteamOS Archive") { installSteamOS(from: SteamOSInstaller.preparedArchiveURL) }
                            .disabled(steamManifest == nil || free < (steamManifest?.requiredFreeBytes ?? Int64.max))
                    }
                }
                if let failure = steamos.failure { Text(failure).foregroundStyle(.red) }
                if steamManifest == nil { Text("This build has no supported SteamOS manifest.").foregroundStyle(.secondary) }
            } footer: { Text("Downloads Valve's SteamFrame recovery image from Valve's server, checks its published SHA-256, and installs its ARM64 system with a terminal and the Plasma X11 desktop.") }
        } else if distribution == "alpine" {
            Section { if manager.busy { ProgressView("Unpacking Alpine Linux…") } else { Button("Install Alpine") { startInstall() } }
                if let error = manager.error { Text(error).foregroundStyle(.red) } }
        } else {
            Section {
                if mainstream.running {
                    Text(mainstream.message)
                    ProgressView(value: mainstream.fraction)
                    Button("Cancel", role: .destructive) { mainstream.cancel() }
                } else {
                    Button("Choose ARM64 Rootfs Archive (.tar.gz / .tar.xz)…") { customRootfsImporter = true }
                }
                if let failure = mainstream.failure { Text(failure).foregroundStyle(.red) }
            } footer: { Text("Import any ARM64 Linux rootfs archive from the Files app.") }
        }
    }

    @ViewBuilder private var account: some View {
        if !LRRuntimeBridge.isRunning() || (!setupRoot.isEmpty && LRRuntimeBridge.activeRootName() != setupRoot) {
            Section { Text("Close L2iOS completely and open it again to continue.") }
        } else {
            let existing = LRRuntimeBridge.linuxAccounts().filter { $0["name"] != "root" && ($0["uid"].flatMap(Int.init) ?? 0) >= 1000 }
            if !existing.isEmpty {
                Section("Use an existing account") {
                    ForEach(existing, id: \.self) { account in Button(account["name"] ?? "") { useAccount(account["name"] ?? "") }.disabled(working != nil) }
                }
            }
            Section(existing.isEmpty ? "Create your account" : "Or create a new account") {
                TextField("Username", text: $username).textInputAutocapitalization(.never).autocorrectionDisabled().textContentType(.username)
                SecureField("Password", text: $password).textContentType(.newPassword)
                SecureField("Confirm password", text: $confirmation).textContentType(.newPassword)
                Toggle("Administrator (can use sudo)", isOn: $administrator)
                Button("Create Account") { createAccount() }.disabled(working != nil || username.isEmpty || password.isEmpty || password != confirmation)
                if !confirmation.isEmpty && password != confirmation { Text("The passwords do not match.").font(.footnote).foregroundStyle(.orange) }
            }
            Section { Text("Lowercase letters, digits, - and _. L2iOS stores only Linux's own password hash, never the password.").font(.footnote).foregroundStyle(.secondary) }
        }
    }

    @ViewBuilder private var desktop: some View {
        if LRRuntimeBridge.activeEnvironmentIsSteamOS() {
            Section {
                Label("SteamOS Plasma X11", systemImage: "desktopcomputer")
                Text("SteamOS includes the Plasma desktop; L2iOS adds its display bridge. This experiment uses software rendering.")
                if desktopReady { Label("Desktop components checked", systemImage: "checkmark"); Button("Continue") { stepRaw = SetupStep.done.rawValue } }
                else { Button("Check SteamOS Desktop") { prepareDesktop() }.disabled(working != nil) }
            }
        } else {
        let distro = DesktopCatalog.activeDistribution()
        Section(header: Text("Choose a Desktop"), footer: Text("Each desktop comes from \(DesktopCatalog.distributionName(distro))'s own packages (network needed). The display, input and file-sharing components every desktop uses are installed first. You can add or switch desktops later in Settings › Desktop Environment; existing settings and files are kept.")) {
            // Only desktops this distribution can install and start are listed.
            ForEach(DesktopCatalog.options.filter { DesktopCatalog.unavailableReason($0.id, distro) == nil }) { option in desktopChoiceRow(option, distro: distro) }
        }
        .onAppear {
            // Each distribution's own desktop is the default: Kali's Xfce, Zorin Desktop on Zorin OS.
            if (distro == "kali" || distro == "void") && chosenDesktop == "linuxrunner" { chosenDesktop = "xfce" }
            if LRRuntimeBridge.activeFlavor() == "zorin" && chosenDesktop == "linuxrunner" { chosenDesktop = "gnome" }
            // Pop!_OS: Xfce until COSMIC's panel and dock are shown (COSMIC stays
            // selectable as experimental).
            if (LRRuntimeBridge.activeFlavor() == "pop" || LRRuntimeBridge.activeFlavor() == "xubuntu") && chosenDesktop == "linuxrunner" { chosenDesktop = "xfce" }
            if LRRuntimeBridge.activeFlavor() == "lubuntu" && chosenDesktop == "linuxrunner" { chosenDesktop = "lxqt" }
        }
        Section {
            let chosen = DesktopCatalog.option(chosenDesktop)
            if let working {
                HStack { ProgressView(); Text(working).font(.callout) }
            } else if desktopReady && DesktopCatalog.isInstalled(chosen.id) {
                Label("\(chosen.title) is installed and selected", systemImage: "checkmark.circle.fill")
                Button("Continue") { stepRaw = SetupStep.done.rawValue }
            } else {
                Button(DesktopCatalog.isInstalled(chosen.id) && desktopReady ? "Use \(chosen.title)" : "Install \(chosen.title)") { installChosenDesktop() }
                    .disabled(DesktopCatalog.unavailableReason(chosen.id, distro) != nil)
                if problem != nil { Button("Retry") { installChosenDesktop() } }
            }
        } footer: {
            if problem != nil { Text("The package log is kept; Settings › Repair Center can check and repair the package database without deleting your files.") }
        }
        if distro == "kali" && desktopReady {
            Section(header: Text("Kali Tools (Optional)"), footer: Text("Kali's standard tool selection (kali-linux-default) from Kali's signed archive: about 1.5 GB to download and 6 GB installed. Tools that need kernel access, such as monitor-mode Wi-Fi, raw packet capture or kernel modules, install but cannot use those features on iOS.")) {
                if LRRuntimeBridge.kaliToolsInstalled() || extraDesktops.contains("kali-tools") { Label("Kali standard tools installed", systemImage: "checkmark") }
                else {
                    Button("Install Kali Standard Tools") {
                        problem = nil; working = "Kali tools: starting"
                        LRRuntimeBridge.installKaliTools({ working = "Kali tools: \($0)" }) { error in
                            working = nil
                            if let error { problem = error.localizedDescription } else { extraDesktops.insert("kali-tools") }
                        }
                    }.disabled(working != nil)
                }
            }
        }
        }
    }

    @ViewBuilder private func desktopChoiceRow(_ option: DesktopOption, distro: String) -> some View {
        let reason = DesktopCatalog.unavailableReason(option.id, distro)
        let selected = chosenDesktop == option.id && reason == nil
        Button { if reason == nil { chosenDesktop = option.id; problem = nil } } label: {
            HStack(alignment: .top, spacing: 12) {
                DesktopBadge(desktopID: option.id, size: 40)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(option.title).foregroundStyle(reason == nil ? Color.primary : Color.secondary)
                        ForEach(option.badges(distro), id: \.self) { badge in
                            Text(badge).font(.caption2.weight(.semibold)).padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Capsule().fill((badge == "Recommended" ? Color.accentColor : Color.secondary).opacity(0.15)))
                        }
                        if DesktopCatalog.isInstalled(option.id) && desktopReady { Text("Installed").font(.caption2).foregroundStyle(.green) }
                    }
                    Text(option.detail).font(.caption).foregroundStyle(.secondary)
                    if let reason { Label(reason, systemImage: "info.circle").font(.caption).foregroundStyle(.orange) }
                }
                Spacer(minLength: 4)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(reason == nil ? Color.accentColor : Color.secondary).font(.title3)
            }
        }
        .disabled(working != nil || reason != nil)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityHint(reason ?? "Selects this desktop")
    }

    private func row(_ title: String, _ value: String) -> some View { HStack { Text(title); Spacer(); Text(value).foregroundStyle(.secondary) } }

    private func resume() {
        if step == .relaunch, LRRuntimeBridge.isRunning(), LRRuntimeBridge.activeRootName() == setupRoot { stepRaw = SetupStep.account.rawValue }
    }

    private func configureExisting(_ environment: LinuxEnvironment) {
        problem = nil; desktopReady = false
        setupRoot = environment.rootfsName
        distribution = environment.distributionID ?? "alpine"
        LRRuntimeBridge.setNextRootName(environment.rootfsName)
        stepRaw = manager.active(environment) ? SetupStep.account.rawValue : SetupStep.relaunch.rawValue
    }

    private func startInstall() {
        guard !anyInstalling else { return }
        problem = nil
        let known = Set(manager.environments.map(\.rootfsName))
        let finish: (String) -> Void = { root in
            setupRoot = root; LRRuntimeBridge.setNextRootName(root)
            stepRaw = (LRRuntimeBridge.isRunning() && LRRuntimeBridge.activeRootName() == root) ? SetupStep.account.rawValue : SetupStep.relaunch.rawValue
        }
        if distribution == "debian" {
            debian.install { environment in manager.acceptInstalled(environment); finish(environment.rootfsName) }
        } else if distribution == "arch" {
            arch.install { environment in manager.acceptInstalled(environment); finish(environment.rootfsName) }
        } else if distribution == "fedora" {
            fedora.install { environment in manager.acceptInstalled(environment); finish(environment.rootfsName) }
        } else if distribution == "kali" {
            kali.install { environment in manager.acceptInstalled(environment); finish(environment.rootfsName) }
        } else if ["ubuntu", "pop", "zorin", "kubuntu", "xubuntu", "lubuntu"].contains(distribution) {
            ubuntu.flavor = UbuntuFlavor(rawValue: distribution)
            ubuntu.install { environment in manager.acceptInstalled(environment); finish(environment.rootfsName) }
        } else if distribution == "void" {
            voidInstaller.install { environment in manager.acceptInstalled(environment); finish(environment.rootfsName) }
        } else if let spec = MainstreamDistroSpec.spec(for: distribution) {
            mainstream.install(spec: spec) { environment in manager.acceptInstalled(environment); finish(environment.rootfsName) }
        } else if distribution == "alpine" {
            manager.error = nil; manager.create(name: "Alpine Linux")
            Task { @MainActor in
                while manager.busy { try? await Task.sleep(nanoseconds: 300_000_000) }
                if let created = manager.environments.first(where: { !known.contains($0.rootfsName) }) { finish(created.rootfsName) }
            }
        } else { problem = "Choose a supported Linux distribution before installing." }
    }

    private func installSteamOSFromValve() {
        guard !debian.running, !arch.running, !fedora.running, !kali.running, !ubuntu.running, !steamos.running, !manager.busy else { return }
        problem = nil
        steamos.installFromValve { environment in
            manager.acceptInstalled(environment)
            setupRoot = environment.rootfsName
            LRRuntimeBridge.setNextRootName(environment.rootfsName)
            stepRaw = SetupStep.relaunch.rawValue
        }
    }

    private func installSteamOS(from source: URL) {
        guard !debian.running, !arch.running, !fedora.running, !kali.running, !ubuntu.running, !steamos.running, !manager.busy else { return }
        problem = nil
        steamos.install(source: source) { environment in
            manager.acceptInstalled(environment)
            setupRoot = environment.rootfsName
            LRRuntimeBridge.setNextRootName(environment.rootfsName)
            stepRaw = SetupStep.relaunch.rawValue
        }
    }

    private func createAccount() {
        problem = nil; working = "Preparing"
        LRRuntimeBridge.createLinuxUser(username, password: password, administrator: administrator, progress: { working = $0 }) { error in
            working = nil
            if let error { problem = error.localizedDescription; return }
            password = ""; confirmation = ""
            useAccount(username)
        }
    }

    private func useAccount(_ name: String) {
        do { try LRRuntimeBridge.setDefaultLinuxUser(name); problem = nil; stepRaw = SetupStep.desktop.rawValue }
        catch { problem = error.localizedDescription }
    }

    // Base components first (every desktop session uses them), then the chosen
    // desktop. Stages are numbered so progress is meaningful; failures keep the
    // log and leave the previous desktop selected.
    private func installChosenDesktop() {
        let option = DesktopCatalog.option(chosenDesktop)
        guard DesktopCatalog.unavailableReason(option.id, DesktopCatalog.activeDistribution()) == nil else { return }
        let needsExtra = option.id != "linuxrunner" && !DesktopCatalog.isInstalled(option.id)
        let total = needsExtra ? 2 : 1
        problem = nil; working = "Step 1 of \(total) · Desktop components: starting"
        LRRuntimeBridge.prepareDesktopProfile({ working = "Step 1 of \(total) · Desktop components: \($0)" }) { error in
            if let error { working = nil; problem = error.localizedDescription; return }
            desktopReady = true
            guard needsExtra, let install = DesktopCatalog.installer(option.id) else { selectDesktop(option.id); return }
            working = "Step 2 of 2 · \(option.title): starting"
            install({ working = "Step 2 of 2 · \(option.title): \($0)" }) { error in
                if let error { working = nil; problem = error.localizedDescription; return }
                selectDesktop(option.id)
            }
        }
    }

    // SteamOS: the image already contains Plasma; this only runs its
    // offline profile check (steamos-profile.sh) and selects Plasma.
    private func prepareDesktop() {
        problem = nil; working = "Checking the SteamOS desktop"
        LRRuntimeBridge.prepareDesktopProfile({ working = $0 }) { error in
            working = nil
            if let error { problem = error.localizedDescription } else { desktopReady = true; selectDesktop("plasma") }
        }
    }

    private func selectDesktop(_ id: String) {
        working = nil
        // Same per-environment choice as Settings › Desktop Environment.
        UserDefaults.standard.set(id, forKey: "LinuxRunnerDesktop.environment." + LRRuntimeBridge.activeRootName())
        extraDesktops.insert(id)
    }
}

struct DesktopOption: Identifiable {
    let id: String
    let title: String
    let detail: String
    let experimental: Bool
    let lightweight: Bool
    func badges(_ distro: String) -> [String] {
        var b: [String] = []
        if id == "linuxrunner" { b.append("Recommended") }
        if lightweight { b.append("Lightweight") }
        if experimental { b.append("Experimental") }
        return b
    }
}

// What each distribution can actually install and start, matching
// desktop-profile.sh. Pickers list only the available ones.
enum DesktopCatalog {
    static var options: [DesktopOption] { [
        DesktopOption(id: "linuxrunner", title: "L2iOS Desktop", detail: "Openbox with a panel and file manager. Fastest start and lowest memory use; best for first-time Linux users.", experimental: false, lightweight: true),
        DesktopOption(id: "xfce", title: "Xfce", detail: "The Xfce desktop: panel, menu, Thunar file manager and settings. On Kali, Kali's own desktop with its menu, themes and wallpaper.", experimental: false, lightweight: true),
        DesktopOption(id: "lxqt", title: "LXQt", detail: "A light, traditional Qt desktop with a start menu, panel and file manager.", experimental: false, lightweight: true),
        DesktopOption(id: "i3", title: "i3", detail: "An X11 tiling window manager. Super+Enter opens a terminal; Super+D opens the application launcher.", experimental: true, lightweight: true),
        LRRuntimeBridge.activeFlavor() == "zorin"
            ? DesktopOption(id: "gnome", title: "Zorin Desktop", detail: "Zorin OS's own desktop: GNOME Shell with the Zorin menu, taskbar, desktop icons, tiling and Zorin themes. Requires a regular user and substantial memory.", experimental: true, lightweight: false)
            : DesktopOption(id: "gnome", title: "Ubuntu GNOME", detail: "Ubuntu's GNOME Shell, dock, Yaru theme and wallpapers. Requires a regular user and substantial memory.", experimental: true, lightweight: false),
        DesktopOption(id: "wayfire", title: "Wayfire", detail: "A Wayland compositor with a panel and dock, running in the X display.", experimental: false, lightweight: false),
        DesktopOption(id: "enlightenment", title: "Enlightenment", detail: "A distinctive desktop with its own compositor; large download.", experimental: false, lightweight: false),
        DesktopOption(id: "plasma", title: "KDE Plasma", detail: "The full KDE desktop. Heaviest option: slowest start and highest memory use.", experimental: true, lightweight: false),
        DesktopOption(id: "hyprland", title: "Hyprland", detail: "A tiling Wayland compositor with Waybar, for keyboard-driven use.", experimental: true, lightweight: false),
        DesktopOption(id: "mate", title: "MATE", detail: "A classic, traditional desktop (the continuation of GNOME 2): panel, menus and the Caja file manager. Light and familiar.", experimental: true, lightweight: true),
        DesktopOption(id: "cinnamon", title: "Cinnamon", detail: "Linux Mint's desktop: a Windows-like taskbar and menu. Composites on the GPU when Metal GPU is active.", experimental: true, lightweight: false),
        DesktopOption(id: "cosmic", title: "COSMIC", detail: "Pop!_OS's own desktop by System76, on the GPU. Experimental: the desktop and apps run, but the panel and dock are not shown yet.", experimental: true, lightweight: false),
        DesktopOption(id: "budgie", title: "Budgie", detail: "A modern, elegant desktop with a clean panel and the Raven side bar. Requires a regular user.", experimental: true, lightweight: false),
        DesktopOption(id: "fluxbox", title: "Fluxbox", detail: "Ultra-lightweight stacking window manager with a built-in toolbar and right-click app menu. Starts almost instantly with minimal RAM.", experimental: false, lightweight: true),
        DesktopOption(id: "icewm", title: "IceWM", detail: "Fast, classic X11 desktop with a taskbar, start menu and low memory footprint.", experimental: false, lightweight: true),
        DesktopOption(id: "sway", title: "Sway", detail: "i3-compatible Wayland tiling compositor with Waybar and Foot terminal.", experimental: true, lightweight: true),
    ] }
    static func option(_ id: String) -> DesktopOption { options.first { $0.id == id } ?? options[0] }
    static func activeDistribution() -> String {
        if LRRuntimeBridge.activeEnvironmentIsKali() { return "kali" }
        if LRRuntimeBridge.activeEnvironmentIsUbuntu() { return "ubuntu" }
        if LRRuntimeBridge.activeEnvironmentIsDebian() { return "debian" }
        if LRRuntimeBridge.activeEnvironmentIsArch() { return "arch" }
        if LRRuntimeBridge.activeEnvironmentIsFedora() { return "fedora" }
        if LRRuntimeBridge.activeEnvironmentIsVoid() { return "void" }
        return "alpine"
    }
    static func distributionName(_ d: String) -> String {
        if d == "ubuntu", let flavor = LRRuntimeBridge.activeFlavor().flatMap(UbuntuFlavor.init(rawValue:)) { return flavor.name }
        switch d { case "debian": return "Debian"; case "ubuntu": return "Ubuntu"; case "arch": return "Arch Linux ARM"; case "fedora": return "Fedora"; case "kali": return "Kali Linux"; case "void": return "Void Linux"; default: return "Alpine Linux" }
    }
    static func unavailableReason(_ id: String, _ d: String) -> String? {
        switch (id, d) {
        case ("linuxrunner", _): return nil
        case ("xfce", "void"): return nil   // Void's own desktop
        case (_, "void"): return "Not yet tested on Void Linux in L2iOS."
        case ("i3", _) where LRRuntimeBridge.activeEnvironmentIsSteamOS(): return "i3 installation is not available for this environment."
        case ("i3", "debian"), ("i3", "ubuntu"), ("i3", "kali"), ("i3", "arch"), ("i3", "fedora"), ("i3", "alpine"): return nil
        case ("fluxbox", "debian"), ("fluxbox", "ubuntu"), ("fluxbox", "kali"), ("fluxbox", "arch"), ("fluxbox", "fedora"), ("fluxbox", "alpine"): return nil
        case ("icewm", "debian"), ("icewm", "ubuntu"), ("icewm", "kali"), ("icewm", "arch"), ("icewm", "fedora"), ("icewm", "alpine"): return nil
        case ("sway", "debian"), ("sway", "ubuntu"), ("sway", "arch"), ("sway", "fedora"): return nil
        case ("sway", _): return "Sway requires Debian, Ubuntu, Arch Linux ARM, or Fedora."
        case ("gnome", "ubuntu"): return nil
        case ("gnome", _): return "Ubuntu GNOME is currently available only for Ubuntu."
        case ("cosmic", "ubuntu") where LRRuntimeBridge.activeFlavor() == "pop": return nil
        case ("cosmic", _): return "COSMIC is Pop!_OS's desktop; it is offered on Pop!_OS."
        case ("mate", "ubuntu"), ("cinnamon", "ubuntu"), ("budgie", "ubuntu"), ("xfce", "ubuntu"): return nil
        case (_, "ubuntu"): return "This Ubuntu desktop has not yet been tested in L2iOS."
        case ("xfce", "kali"), ("xfce", "debian"): return nil
        case ("xfce", _): return "Offered on Debian, Ubuntu-based distributions and Kali; not yet tested on this distribution."
        case (_, "kali") where id != "linuxrunner": return "Kali's desktop is Xfce; other desktops are not yet tested on Kali."
        case ("lxqt", "fedora"): return "Not yet tested with Fedora in L2iOS, so it is not offered yet."
        case ("lxqt", _): return nil
        case ("enlightenment", "debian"): return "Debian's Enlightenment session stops at its splash screen in L2iOS."
        case ("enlightenment", "fedora"): return "Not yet tested with Fedora in L2iOS, so it is not offered yet."
        case ("enlightenment", _): return nil
        case ("wayfire", "alpine"): return "Alpine's packages lack what L2iOS's Wayfire session needs."
        case ("wayfire", _): return nil
        case ("plasma", "alpine"): return "L2iOS's Plasma session supports Debian, Arch Linux ARM and Fedora only."
        case ("plasma", _): return nil
        case ("mate", "alpine"), ("mate", "kali"): return "Not yet tested on this distribution in L2iOS."
        case ("mate", _): return nil
        case ("cinnamon", "alpine"), ("budgie", "alpine"): return "Alpine Linux does not package this desktop."
        case ("cinnamon", "kali"), ("budgie", "kali"): return "Not yet tested on this distribution in L2iOS."
        case ("cinnamon", _), ("budgie", _): return nil
        case ("hyprland", "arch"): return nil
        case ("hyprland", "debian"): return "Debian 13 does not package Hyprland; it needs Arch Linux ARM."
        case ("hyprland", _): return "Needs Arch Linux ARM, which packages Hyprland for this setup."
        default: return "Not available."
        }
    }
    static func isInstalled(_ id: String) -> Bool {
        switch id {
        case "xfce": return LRRuntimeBridge.xfceInstalled()
        case "lxqt": return LRRuntimeBridge.lxqtInstalled()
        case "i3": return LRRuntimeBridge.i3Installed()
        case "gnome": return LRRuntimeBridge.gnomeInstalled()
        case "enlightenment": return LRRuntimeBridge.enlightenmentInstalled()
        case "wayfire": return LRRuntimeBridge.wayfireInstalled()
        case "plasma": return LRRuntimeBridge.plasmaInstalled()
        case "hyprland": return LRRuntimeBridge.hyprlandInstalled()
        case "mate", "cinnamon", "budgie", "cosmic", "fluxbox", "icewm", "sway": return LRRuntimeBridge.desktopInstalled(id)
        default: return true // part of the desktop components
        }
    }
    static func installer(_ id: String) -> ((@escaping (String) -> Void, @escaping (Error?) -> Void) -> Void)? {
        switch id {
        case "xfce": return { LRRuntimeBridge.installXfce($0, completion: $1) }
        case "lxqt": return { LRRuntimeBridge.installLXQt($0, completion: $1) }
        case "i3": return { LRRuntimeBridge.installI3($0, completion: $1) }
        case "gnome": return { LRRuntimeBridge.installGnome($0, completion: $1) }
        case "enlightenment": return { LRRuntimeBridge.installEnlightenment($0, completion: $1) }
        case "wayfire": return { LRRuntimeBridge.installWayfire($0, completion: $1) }
        case "plasma": return { LRRuntimeBridge.installPlasma($0, completion: $1) }
        case "hyprland": return { LRRuntimeBridge.installHyprland($0, completion: $1) }
        case "mate", "cinnamon", "budgie", "cosmic", "fluxbox", "icewm", "sway": return { LRRuntimeBridge.installDesktop(id, progress: $0, completion: $1) }
        default: return nil
        }
    }
}

struct MainstreamDistroSpec {
    let id: String
    let displayName: String
    let lxcDistro: String
    let lxcRelease: String
    let lxcVariant: String
    let distributionID: String
    let packageManager: String
    let version: String

    static func spec(for id: String) -> MainstreamDistroSpec? {
        switch id {
        case "opensuse":
            return MainstreamDistroSpec(id: "opensuse", displayName: "openSUSE Tumbleweed", lxcDistro: "opensuse", lxcRelease: "tumbleweed", lxcVariant: "default", distributionID: "opensuse", packageManager: "zypper", version: "Tumbleweed")
        case "opensuse-leap":
            return MainstreamDistroSpec(id: "opensuse-leap", displayName: "openSUSE Leap 15.6", lxcDistro: "opensuse", lxcRelease: "15.6", lxcVariant: "default", distributionID: "opensuse", packageManager: "zypper", version: "15.6")
        case "rocky":
            return MainstreamDistroSpec(id: "rocky", displayName: "Rocky Linux 9", lxcDistro: "rockylinux", lxcRelease: "9", lxcVariant: "default", distributionID: "fedora", packageManager: "dnf", version: "9")
        case "rocky-8":
            return MainstreamDistroSpec(id: "rocky-8", displayName: "Rocky Linux 8", lxcDistro: "rockylinux", lxcRelease: "8", lxcVariant: "default", distributionID: "fedora", packageManager: "dnf", version: "8")
        case "almalinux":
            return MainstreamDistroSpec(id: "almalinux", displayName: "AlmaLinux 9", lxcDistro: "almalinux", lxcRelease: "9", lxcVariant: "default", distributionID: "fedora", packageManager: "dnf", version: "9")
        case "almalinux-8":
            return MainstreamDistroSpec(id: "almalinux-8", displayName: "AlmaLinux 8", lxcDistro: "almalinux", lxcRelease: "8", lxcVariant: "default", distributionID: "fedora", packageManager: "dnf", version: "8")
        case "centos":
            return MainstreamDistroSpec(id: "centos", displayName: "CentOS Stream 9", lxcDistro: "centos", lxcRelease: "9-Stream", lxcVariant: "default", distributionID: "fedora", packageManager: "dnf", version: "9-Stream")
        case "oracle":
            return MainstreamDistroSpec(id: "oracle", displayName: "Oracle Linux 9", lxcDistro: "oracle", lxcRelease: "9", lxcVariant: "default", distributionID: "fedora", packageManager: "dnf", version: "9")
        case "fedora-41":
            return MainstreamDistroSpec(id: "fedora-41", displayName: "Fedora 41", lxcDistro: "fedora", lxcRelease: "41", lxcVariant: "default", distributionID: "fedora", packageManager: "dnf", version: "41")
        case "debian-bookworm":
            return MainstreamDistroSpec(id: "debian-bookworm", displayName: "Debian 12 (Bookworm)", lxcDistro: "debian", lxcRelease: "bookworm", lxcVariant: "default", distributionID: "debian", packageManager: "apt", version: "12")
        case "debian-sid":
            return MainstreamDistroSpec(id: "debian-sid", displayName: "Debian Sid", lxcDistro: "debian", lxcRelease: "sid", lxcVariant: "default", distributionID: "debian", packageManager: "apt", version: "sid")
        case "ubuntu-jammy":
            return MainstreamDistroSpec(id: "ubuntu-jammy", displayName: "Ubuntu 22.04 LTS", lxcDistro: "ubuntu", lxcRelease: "jammy", lxcVariant: "default", distributionID: "ubuntu", packageManager: "apt", version: "22.04")
        case "ubuntu-oracular":
            return MainstreamDistroSpec(id: "ubuntu-oracular", displayName: "Ubuntu 24.10", lxcDistro: "ubuntu", lxcRelease: "oracular", lxcVariant: "default", distributionID: "ubuntu", packageManager: "apt", version: "24.10")
        case "devuan":
            return MainstreamDistroSpec(id: "devuan", displayName: "Devuan 5 Daedalus", lxcDistro: "devuan", lxcRelease: "daedalus", lxcVariant: "default", distributionID: "debian", packageManager: "apt", version: "5")
        case "gentoo":
            return MainstreamDistroSpec(id: "gentoo", displayName: "Gentoo Linux", lxcDistro: "gentoo", lxcRelease: "current", lxcVariant: "openrc", distributionID: "gentoo", packageManager: "emerge", version: "rolling")
        case "alpine-edge":
            return MainstreamDistroSpec(id: "alpine-edge", displayName: "Alpine Edge", lxcDistro: "alpine", lxcRelease: "edge", lxcVariant: "default", distributionID: "alpine", packageManager: "apk", version: "edge")
        case "busybox":
            return MainstreamDistroSpec(id: "busybox", displayName: "BusyBox Minimal", lxcDistro: "busybox", lxcRelease: "1.36.1", lxcVariant: "default", distributionID: "alpine", packageManager: "sh", version: "1.36.1")
        default:
            return nil
        }
    }
}

private final class MainstreamCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var stopped = false
    func cancel() { lock.lock(); stopped = true; lock.unlock() }
    func check() -> Bool { lock.lock(); defer { lock.unlock() }; return stopped }
}

@MainActor final class MainstreamDistroInstaller: ObservableObject {
    @Published var message = "Ready"
    @Published var fraction = 0.0 { didSet { if let longTask { LongTaskCenter.shared.update(longTask, detail: message, fraction: fraction) } } }
    private var longTask: String?
    @Published var running = false {
        didSet {
            if running != oldValue {
                running ? LRRuntimeBridge.beginAwake("mainstream-install") : LRRuntimeBridge.endAwake("mainstream-install")
                if running { longTask = LongTaskCenter.shared.begin(title: "Installing Linux", detail: message, userStarted: true) }
                else if let token = longTask { longTask = nil; LongTaskCenter.shared.end(token, success: failure == nil, message: failure ?? message) }
            }
        }
    }
    @Published var failure: String?
    private var operation: Task<Void, Never>?
    private var cancellation = MainstreamCancellation()

    func cancel() { cancellation.cancel(); operation?.cancel() }

    func install(spec: MainstreamDistroSpec, completion: @escaping (LinuxEnvironment) -> Void) {
        guard !running else { return }
        running = true; failure = nil; fraction = 0; cancellation = MainstreamCancellation()
        let token = cancellation
        message = "Fetching \(spec.displayName) mirror index…"
        operation = Task {
            defer { running = false }
            do {
                let indexURL = URL(string: "https://images.linuxcontainers.org/meta/1.0/index-user")!
                let (indexData, indexResp) = try await URLSession.shared.data(from: indexURL)
                guard (indexResp as? HTTPURLResponse)?.statusCode == 200,
                      let indexText = String(data: indexData, encoding: .utf8) else {
                    throw NSError(domain: "L2iOS", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not reach official ARM64 image index."])
                }
                let matches = indexText.components(separatedBy: .newlines).compactMap { line -> String? in
                    let cols = line.components(separatedBy: ";")
                    guard cols.count >= 6,
                          cols[0] == spec.lxcDistro,
                          cols[1] == spec.lxcRelease,
                          cols[2] == "arm64",
                          cols[3] == spec.lxcVariant else { return nil }
                    return cols[5]
                }
                guard let path = matches.last else {
                    throw NSError(domain: "L2iOS", code: 2, userInfo: [NSLocalizedDescriptionKey: "No ARM64 build found for \(spec.displayName) in mirror index."])
                }
                let baseURL = "https://images.linuxcontainers.org" + (path.hasSuffix("/") ? path : path + "/")
                message = "Verifying \(spec.displayName) checksum…"
                fraction = 0.08
                let (sumData, _) = try await URLSession.shared.data(from: URL(string: baseURL + "SHA256SUMS")!)
                let sumText = String(data: sumData, encoding: .utf8) ?? ""
                let expectedSHA = sumText.components(separatedBy: .newlines).compactMap { line -> String? in
                    let parts = line.split(whereSeparator: \.isWhitespace)
                    guard parts.count >= 2, parts[1].hasSuffix("rootfs.tar.xz") else { return nil }
                    return String(parts[0]).lowercased()
                }.first

                message = "Downloading \(spec.displayName) ARM64 rootfs…"
                fraction = 0.15
                let (downloaded, dlResp) = try await URLSession.shared.download(from: URL(string: baseURL + "rootfs.tar.xz")!)
                defer { try? FileManager.default.removeItem(at: downloaded) }
                guard (dlResp as? HTTPURLResponse)?.statusCode == 200 else {
                    throw NSError(domain: "L2iOS", code: 3, userInfo: [NSLocalizedDescriptionKey: "Download failed for \(spec.displayName)."])
                }
                if token.check() { throw CancellationError() }

                message = "Checking SHA-256 integrity…"
                fraction = 0.55
                let actualSHA = try DebianInstaller.sha256(downloaded)
                if let expectedSHA, expectedSHA != actualSHA {
                    throw NSError(domain: "L2iOS", code: 4, userInfo: [NSLocalizedDescriptionKey: "SHA-256 mismatch for \(spec.displayName)."])
                }

                let root = UUID().uuidString.lowercased()
                message = "Importing \(spec.displayName) filesystem…"
                let metadata: [String: String] = [
                    "distributionID": spec.distributionID,
                    "distribution": spec.displayName,
                    "flavor": spec.id,
                    "version": spec.version,
                    "packageManager": spec.packageManager,
                    "defaultShell": "/bin/bash"
                ]
                try await Task.detached(priority: .utility) {
                    try LRRuntimeBridge.importVerifiedEnvironment(downloaded, root: root, sha256: actualSHA, metadata: metadata, progress: { value, _ in
                        Task { @MainActor in self.fraction = 0.6 + value * 0.4 }
                    }, cancel: { token.check() })
                }.value

                var env = LinuxEnvironment(name: spec.displayName, rootfsName: root)
                env.distribution = spec.displayName
                env.distributionID = spec.distributionID
                env.flavor = spec.id
                env.packageManager = spec.packageManager
                env.rootfsVersion = spec.version
                env.defaultShell = "/bin/bash"
                env.installationState = "Imported"
                env.guiAvailability = "Not installed"
                env.desktopAvailability = "Not installed"
                completion(env)
                message = "Imported \(spec.displayName)."
                fraction = 1.0
            } catch {
                failure = (error is CancellationError || token.check()) ? "Installation cancelled." : error.localizedDescription
            }
        }
    }

    func importLocalArchive(url: URL, completion: @escaping (LinuxEnvironment) -> Void) {
        guard !running else { return }
        running = true; failure = nil; fraction = 0.1; cancellation = MainstreamCancellation()
        let token = cancellation
        let name = url.deletingPathExtension().deletingPathExtension().lastPathComponent
        message = "Importing \(name)…"
        operation = Task {
            defer { running = false }
            do {
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                let sha = try DebianInstaller.sha256(url)
                let root = UUID().uuidString.lowercased()
                let metadata: [String: String] = [
                    "distributionID": "debian",
                    "distribution": name.isEmpty ? "Custom Linux" : name,
                    "version": "custom",
                    "packageManager": "sh",
                    "defaultShell": "/bin/sh"
                ]
                try await Task.detached(priority: .utility) {
                    try LRRuntimeBridge.importVerifiedEnvironment(url, root: root, sha256: sha, metadata: metadata, progress: { value, _ in
                        Task { @MainActor in self.fraction = 0.2 + value * 0.8 }
                    }, cancel: { token.check() })
                }.value
                var env = LinuxEnvironment(name: name.isEmpty ? "Custom Linux" : name, rootfsName: root)
                env.distribution = env.name
                env.distributionID = "debian"
                env.packageManager = "sh"
                env.rootfsVersion = "custom"
                env.defaultShell = "/bin/sh"
                env.installationState = "Imported"
                completion(env)
                message = "Imported \(env.name)."
                fraction = 1.0
            } catch {
                failure = error.localizedDescription
            }
        }
    }

    func importFromURL(_ urlString: String, name: String, completion: @escaping (LinuxEnvironment) -> Void) {
        guard !running, let url = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["https", "http"].contains(url.scheme?.lowercased() ?? "") else {
            failure = "Enter a valid http:// or https:// rootfs archive URL."
            return
        }
        running = true; failure = nil; fraction = 0.05; cancellation = MainstreamCancellation()
        let token = cancellation
        let label = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Custom Linux" : name.trimmingCharacters(in: .whitespacesAndNewlines)
        message = "Downloading \(label)…"
        operation = Task {
            defer { running = false }
            do {
                let (downloaded, resp) = try await URLSession.shared.download(from: url)
                defer { try? FileManager.default.removeItem(at: downloaded) }
                guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
                    throw NSError(domain: "L2iOS", code: 5, userInfo: [NSLocalizedDescriptionKey: "Failed to download archive from URL."])
                }
                if token.check() { throw CancellationError() }
                message = "Verifying & importing \(label)…"
                fraction = 0.5
                let sha = try DebianInstaller.sha256(downloaded)
                let root = UUID().uuidString.lowercased()
                let metadata: [String: String] = [
                    "distributionID": "debian",
                    "distribution": label,
                    "version": "custom",
                    "packageManager": "sh",
                    "defaultShell": "/bin/sh"
                ]
                try await Task.detached(priority: .utility) {
                    try LRRuntimeBridge.importVerifiedEnvironment(downloaded, root: root, sha256: sha, metadata: metadata, progress: { value, _ in
                        Task { @MainActor in self.fraction = 0.5 + value * 0.5 }
                    }, cancel: { token.check() })
                }.value
                var env = LinuxEnvironment(name: label, rootfsName: root)
                env.distribution = label
                env.distributionID = "debian"
                env.packageManager = "sh"
                env.rootfsVersion = "custom"
                env.defaultShell = "/bin/sh"
                env.installationState = "Imported"
                completion(env)
                message = "Imported \(label)."
                fraction = 1.0
            } catch {
                failure = (error is CancellationError || token.check()) ? "Cancelled." : error.localizedDescription
            }
        }
    }
}

