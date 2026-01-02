import AppKit
import Darwin
import MachO
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject var appStore: AppStore
    @ObservedObject private var controllerManager = ControllerInputManager.shared
    @Environment(\.colorScheme) private var colorScheme
    private enum ShortcutTarget {
        case launchpad
        // case aiOverlay
    }
    @State private var showResetConfirm = false
    @State private var selectedSection: SettingsSection = .general
    @State private var titleSearch: String = ""
    @State private var hiddenSearch: String = ""
    @State private var editingDrafts: [String: String] = [:]
    @State private var editingEntries: Set<String> = []
    @State private var iconImportError: String? = nil
    @State private var showAppSourcesResetDialog = false
    @State private var showUpdateNotes = false
    // backup 相关 @State 变量已移除
    @State private var showPerformanceRestartPrompt = false
    @State private var capturingShortcutTarget: ShortcutTarget? = nil
    @State private var shortcutCaptureMonitor: Any?
    @State private var pendingShortcut: AppStore.HotKeyConfiguration?

    // Sidebar sizing presets
    private var sidebarIconFrame: CGFloat {
        switch appStore.sidebarIconPreset {
        case .large: return 26
        case .medium: return 24
        }
    }

    private var sidebarIconFontSize: CGFloat {
        switch appStore.sidebarIconPreset {
        case .large: return 13
        case .medium: return 12
        }
    }

    private var sidebarRowVerticalPadding: CGFloat {
        switch appStore.sidebarIconPreset {
        case .large: return 2
        case .medium: return 1
        }
    }

    private var sidebarHeaderIconFrame: CGFloat {
        return 36
    }

    private var sidebarHeaderCornerRadius: CGFloat {
        switch appStore.sidebarIconPreset {
        case .large: return 3
        case .medium: return 3
        }
    }

    private var visibleSections: [SettingsSection] {
        SettingsSection.allCases.filter { section in
            if section == .updates {
                return false  // Always hide updates for App Store release
            }
            if section == .development {
                return false  // Always hide development section
            }
            return true
        }
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            NavigationSplitView {
                List(selection: $selectedSection) {
                    HStack(alignment: .center, spacing: 2) {
                        Image(nsImage: NSApplication.shared.applicationIconImage)
                            .resizable()
                            .interpolation(.high)
                            .antialiased(true)
                            .frame(width: sidebarHeaderIconFrame, height: sidebarHeaderIconFrame)
                            .cornerRadius(sidebarHeaderCornerRadius)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(appStore.localized(.appTitle))
                                .font(.headline.weight(.semibold))
                            Text(
                                "\(appStore.localized(.versionPrefix))\(getVersion(fallback: appStore.localized(.versionFallback)))"
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.bottom, 17)
                    .listRowInsets(EdgeInsets(top: 0, leading: -4, bottom: 15, trailing: 10))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)

                    ForEach(visibleSections) { section in
                        HStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(section.iconGradient)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(Color.black.opacity(0.06))
                                        .blendMode(.multiply)
                                }
                                .overlay {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(
                                            LinearGradient(
                                                colors: [
                                                    .white.opacity(0.45),
                                                    .white.opacity(0.08),
                                                    .clear,
                                                ],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                        .blendMode(.screen)
                                }
                                .overlay {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .stroke(.white.opacity(0.22), lineWidth: 0.5)
                                        .blendMode(.screen)
                                }
                                .overlay(
                                    Image(systemName: section.iconName)
                                        .font(.system(size: sidebarIconFontSize, weight: .semibold))
                                        .foregroundStyle(.white)
                                )
                                .frame(width: sidebarIconFrame, height: sidebarIconFrame)
                                .liquidGlass()
                                .shadow(color: .black.opacity(0.12), radius: 4, x: 0, y: 1)

                            Text(appStore.localized(section.localizationKey))
                                .font(.system(size: 13.5, weight: .regular))
                        }
                        .padding(.vertical, sidebarRowVerticalPadding)
                        .tag(section)
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
                .background(.ultraThinMaterial)
                .navigationSplitViewColumnWidth(min: 180, ideal: 205, max: 250)
            } detail: {
                detailView(for: selectedSection)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.ultraThinMaterial)

            Button {
                appStore.isSetting = false
            } label: {
                Image(systemName: "xmark")
                    .font(.title2.bold())
                    .foregroundStyle(.secondary)
                    .padding(8)
                    .background(
                        Circle()
                            .fill(.ultraThinMaterial)
                            .liquidGlass()
                            .shadow(color: .black.opacity(0.12), radius: 6, x: 0, y: 2)
                    )
            }
            .buttonStyle(.plain)
            .padding(.top, 12)
            .padding(.trailing, 16)
        }
        .frame(minWidth: 820, minHeight: 640)
        .alert(
            appStore.localized(.customIconTitle),
            isPresented: Binding(
                get: { iconImportError != nil }, set: { if !$0 { iconImportError = nil } })
        ) {
            Button(appStore.localized(.okButton), role: .cancel) { iconImportError = nil }
        } message: {
            Text(iconImportError ?? "")
        }
        // .onChange(of: appStore.isAIEnabled) { enabled in
        //     if !enabled && isCapturingShortcut(.aiOverlay) {
        //         stopShortcutCapture(cancel: true)
        //     }
        // }
        .onDisappear {
            stopShortcutCapture(cancel: false)
        }
    }

    private var systemVersionText: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return String(
            format: appStore.localized(.aboutInfoMacOSValueFormat),
            v.majorVersion, v.minorVersion, v.patchVersion)
    }

    private var chipText: String {
        var size: size_t = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        var nameBuffer = [CChar](repeating: 0, count: Int(size))
        if sysctlbyname("machdep.cpu.brand_string", &nameBuffer, &size, nil, 0) == 0 {
            return String(cString: nameBuffer)
        }
        return appStore.localized(.aboutInfoUnknownChip)
    }

    private var displayResolutionText: String {
        guard let screen = NSScreen.main else {
            return appStore.localized(.aboutInfoUnknownDisplay)
        }
        let scale = screen.backingScaleFactor
        let size = screen.frame.size
        let width = Int(size.width * scale)
        let height = Int(size.height * scale)
        return "\(width)×\(height)"
    }

    private var displayNameText: String {
        if let name = NSScreen.main?.localizedName, !name.isEmpty {
            return name
        }
        return appStore.localized(.aboutInfoDisplayGeneric)
    }

    private func getVersion(fallback: String) -> String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? fallback
    }

    private enum SettingsSection: String, CaseIterable, Identifiable {
        case general
        case appearance
        case performance
        case titles
        case appSources
        case hiddenApps
        // case backup - 已移除以符合 App Store 审核指南
        case development
        // case aiOverlay
        case sound
        case gameController
        case updates
        case about

        var id: String { rawValue }

        var iconName: String {
            switch self {
            case .general: return "gearshape"
            case .appSources: return "externaldrive"
            case .gameController: return "gamecontroller"
            case .sound: return "speaker.wave.2"
            case .appearance: return "paintbrush"
            case .performance: return "speedometer"
            case .titles: return "text.badge.plus"
            case .hiddenApps: return "eye.slash"
            case .development: return "hammer"
            // case .aiOverlay: return "sparkles"
            case .updates: return "arrow.down.circle"
            case .about: return "info.circle"
            }
        }

        var iconGradient: LinearGradient {
            let colors: [Color]
            switch self {
            case .general:
                colors = [
                    Color(red: 0.12, green: 0.52, blue: 0.96),
                    Color(red: 0.22, green: 0.72, blue: 0.94),
                ]
            case .appSources:
                colors = [Color(nsColor: .systemGray), Color(nsColor: .lightGray)]
            case .sound:
                colors = [
                    Color(red: 0.92, green: 0.12, blue: 0.12),
                    Color(red: 0.99, green: 0.30, blue: 0.30),
                ]
            case .gameController:
                colors = [
                    Color(red: 0.46, green: 0.34, blue: 0.97),
                    Color(red: 0.31, green: 0.54, blue: 0.99),
                ]
            case .appearance:
                colors = [
                    Color(red: 0.73, green: 0.25, blue: 0.96),
                    Color(red: 0.98, green: 0.43, blue: 0.80),
                ]
            case .performance:
                colors = [
                    Color(red: 0.02, green: 0.70, blue: 0.46),
                    Color(red: 0.31, green: 0.93, blue: 0.69),
                ]
            case .titles:
                colors = [
                    Color(red: 0.95, green: 0.37, blue: 0.32),
                    Color(red: 0.98, green: 0.55, blue: 0.44),
                ]
            case .hiddenApps:
                colors = [
                    Color(red: 0.29, green: 0.39, blue: 0.96),
                    Color(red: 0.11, green: 0.67, blue: 0.91),
                ]
            case .development:
                colors = [
                    Color(red: 0.98, green: 0.58, blue: 0.16),
                    Color(red: 0.96, green: 0.20, blue: 0.24),
                ]
            // case .aiOverlay:
            //     colors = [Color(red: 0.39, green: 0.33, blue: 0.98), Color(red: 0.59, green: 0.73, blue: 0.99)]
            case .updates:
                colors = [
                    Color(red: 0.22, green: 0.78, blue: 0.55),
                    Color(red: 0.10, green: 0.62, blue: 0.91),
                ]
            case .about:
                colors = [
                    Color(red: 0.54, green: 0.55, blue: 0.70),
                    Color(red: 0.42, green: 0.44, blue: 0.60),
                ]
            }
            return LinearGradient(
                gradient: Gradient(colors: colors), startPoint: .topLeading,
                endPoint: .bottomTrailing)
        }

        var localizationKey: LocalizationKey {
            switch self {
            case .general: return .settingsSectionGeneral
            case .appSources: return .settingsSectionAppSources
            case .sound: return .settingsSectionSound
            case .gameController: return .settingsSectionGameController
            case .appearance: return .settingsSectionAppearance
            case .performance: return .settingsSectionPerformance
            case .titles: return .settingsSectionTitles
            case .hiddenApps: return .settingsSectionHiddenApps
            case .development: return .settingsSectionDevelopment
            // case .aiOverlay: return .settingsSectionAIOverlay
            case .updates: return .settingsSectionUpdates
            case .about: return .settingsSectionAbout
            }
        }
    }

    @ViewBuilder
    private func detailView(for section: SettingsSection) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .frame(height: 160)
                    .mask(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.white.opacity(1), Color.white.opacity(0),
                            ]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .allowsHitTesting(false)

                VStack(alignment: .leading, spacing: 16) {
                    Text(appStore.localized(section.localizationKey))
                        .font(.title3.bold())

                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 24) {
                            content(for: section)
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .scrollDisabled(section == .about || section == .general)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .scrollBounceBehavior(.basedOnSize)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            }
            .background(.ultraThinMaterial)
        }
    }

    @ViewBuilder
    private func content(for section: SettingsSection) -> some View {
        switch section {
        case .general:
            generalSection
        case .appearance:
            appearanceSection
        case .performance:
            performanceSection
        case .titles:
            titlesSection
        case .appSources:
            appSourcesSection
        case .hiddenApps:
            hiddenAppsSection
        case .development:
            developmentSection
        // case .aiOverlay:
        //     aiOverlaySection
        case .sound:
            soundSection
        case .gameController:
            gameControllerSection
        case .updates:
            updatesSection
        case .about:
            aboutSection
        }
    }

    private var gameControllerSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 12) {
                Text(appStore.localized(.gameControllerPlaceholderTitle))
                    .font(.headline.weight(.semibold))

                Toggle(isOn: $appStore.gameControllerEnabled) {
                    Text(appStore.localized(.gameControllerToggleTitle))
                        .font(.subheadline.weight(.semibold))
                }
                .toggleStyle(.switch)

                VStack(alignment: .leading, spacing: 6) {
                    Text(gameControllerStatusText)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.primary)

                    Text(appStore.localized(.gameControllerPlaceholderSubtitle))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(nsColor: .quaternarySystemFill))
            )

            VStack(alignment: .leading, spacing: 8) {
                Text(appStore.localized(.gameControllerQuickGuideTitle))
                    .font(.footnote.weight(.semibold))

                VStack(alignment: .leading, spacing: 6) {
                    guideRow(
                        icon: "dpad", text: appStore.localized(.gameControllerQuickGuideDirection))
                    guideRow(
                        icon: "a.circle.fill",
                        text: appStore.localized(.gameControllerQuickGuideSelect))
                    guideRow(
                        icon: "b.circle.fill",
                        text: appStore.localized(.gameControllerQuickGuideCancel))
                }
            }
        }
    }

    private func guideRow(icon: String, text: String) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(Color.accentColor)
                .frame(width: 18)

            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var gameControllerStatusText: String {
        if !appStore.gameControllerEnabled {
            return appStore.localized(.gameControllerStatusDisabled)
        }

        let names = controllerManager.connectedControllerNames
        guard !names.isEmpty else {
            return appStore.localized(.gameControllerStatusNoController)
        }

        let joined = names.joined(separator: ", ")
        return String(format: appStore.localized(.gameControllerStatusConnectedFormat), joined)
    }

    private var soundSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            Toggle(isOn: $appStore.soundEffectsEnabled) {
                Text(appStore.localized(.soundToggleTitle))
                    .font(.subheadline.weight(.semibold))
            }
            .toggleStyle(.switch)

            Text(appStore.localized(.soundToggleDescription))
                .font(.footnote)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 12) {
                soundPickerRow(
                    title: .soundEventLaunchpadOpen, binding: $appStore.soundLaunchpadOpenSound)
                soundPickerRow(
                    title: .soundEventLaunchpadClose, binding: $appStore.soundLaunchpadCloseSound)
                soundPickerRow(
                    title: .soundEventNavigation, binding: $appStore.soundNavigationSound)
            }

            Divider()

            Toggle(isOn: $appStore.voiceFeedbackEnabled) {
                Text(appStore.localized(.voiceToggleTitle))
                    .font(.subheadline.weight(.semibold))
            }
            .toggleStyle(.switch)

            Text(appStore.localized(.voiceToggleDescription))
                .font(.footnote)
                .foregroundStyle(.secondary)

            Text(appStore.localized(.voiceNoteMutualExclusive))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(nsColor: .quaternarySystemFill))
        )
    }

    private func soundPickerRow(title: LocalizationKey, binding: Binding<String>) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(appStore.localized(title))
                .font(.subheadline.weight(.semibold))

            Spacer(minLength: 24)

            Picker("", selection: binding) {
                Text(appStore.localized(.soundOptionNone)).tag("")
                ForEach(SoundManager.systemSoundOptions) { option in
                    Text(option.displayName).tag(option.id)
                }
            }
            .labelsHidden()
            .frame(minWidth: 140)

            Button(appStore.localized(.soundPreviewButton)) {
                SoundManager.shared.preview(systemSoundNamed: binding.wrappedValue)
            }
            .disabled(binding.wrappedValue.isEmpty)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
    }

    // backupSection 及相关函数已移除以符合 App Store 审核指南

    private var developmentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(appStore.localized(.developmentPlaceholderTitle))
                .font(.headline)
            Text(appStore.localized(.developmentPlaceholderSubtitle))
                .font(.footnote)
                .foregroundStyle(.secondary)

            HStack(spacing: 6) {
                Image(systemName: "memorychip")
                Text(currentMemoryUsageString())
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)

            Divider()

            // 已移除旧版导入功能以符合 App Store 审核指南

            Text(appStore.localized(.modifiedFrom))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    // private var aiOverlaySection: some View {
    //     VStack(alignment: .leading, spacing: 20) {
    //         Toggle(isOn: $appStore.isAIEnabled) {
    //             Text(appStore.localized(.aiFeatureToggleTitle))
    //                 .font(.headline)
    //         }
    //         .toggleStyle(.switch)
    //
    //         Text("AI features are experimental. It’s recommended to keep them off unless you’re testing.")
    //             .font(.footnote)
    //             .foregroundStyle(.secondary)
    //
    //         Text(appStore.localized(.aiOverlayShortcutHint))
    //             .font(.footnote)
    //             .foregroundStyle(.secondary)
    //
    //         Button {
    //             appStore.presentAIOverlayPreview()
    //         } label: {
    //             Label(appStore.localized(.aiOverlayPreviewButtonLabel), systemImage: "sparkles")
    //                 .font(.headline)
    //                 .frame(maxWidth: .infinity)
    //                 .padding(.vertical, 6)
    //         }
    //         .buttonStyle(.borderedProminent)
    //         .tint(Color.accentColor)
    //         .disabled(!appStore.isAIEnabled)
    //     }
    //     .frame(maxWidth: .infinity, alignment: .leading)
    // }

    private var performanceSection: some View {
        let stats = appStore.cacheStatistics
        let isLeanMode = appStore.performanceMode == .lean

        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                Text(appStore.localized(.performanceModeTitle))
                    .font(.title3.weight(.semibold))
                Text(appStore.localized(.performanceModeSubtitle))
                    .font(.callout)
                    .foregroundStyle(.secondary)

                performanceModePicker()

                Text(appStore.localized(.performanceModeDescriptionLean))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text(appStore.localized(.performanceModeDescriptionFull))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text(appStore.localized(.performanceModeRestartHint))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .liquidGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text(appStore.localized(.performanceCacheTitle))
                        .font(.title3.weight(.semibold))
                    Spacer()
                    if isLeanMode {
                        leanModeBadge()
                    }
                    cacheStatusBadge(isValid: stats.isCacheValid)
                }

                Text(
                    "\(appStore.localized(.performanceCacheLastUpdateLabel)): \(formattedCacheUpdate(stats.lastUpdate))"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)

                if isLeanMode {
                    Text(appStore.localized(.performanceCacheLeanHint))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    cacheCountRow(
                        title: appStore.localized(.performanceCacheIconLabel),
                        valueText: isLeanMode
                            ? appStore.localized(.performanceCacheIconsDisabled)
                            : "\(stats.iconCacheSize)")
                    cacheCountRow(
                        title: appStore.localized(.performanceCacheAppInfoLabel),
                        valueText: "\(stats.appInfoCacheSize)")
                    cacheCountRow(
                        title: appStore.localized(.performanceCacheGridLabel),
                        valueText: "\(stats.gridLayoutCacheSize)")
                    cacheCountRow(
                        title: appStore.localized(.performanceCacheTotalLabel),
                        valueText: "\(stats.totalCacheSize)")
                }

                Text(appStore.localized(.performanceCacheCountsHint))
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Button {
                    appStore.clearCache()
                    IconStore.shared.clear()
                    FolderPreviewCache.shared.clear()
                } label: {
                    Label(appStore.localized(.performanceCacheClearButton), systemImage: "trash")
                        .font(.footnote.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.bordered)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .liquidGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            Text(appStore.localized(.performanceModeRecommendation))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .onChange(of: appStore.performanceMode) { _, _ in
            showPerformanceRestartPrompt = true
        }
        .alert(
            appStore.localized(.performanceModeRestartTitle),
            isPresented: $showPerformanceRestartPrompt
        ) {
            Button(appStore.localized(.okButton), role: .cancel) {}
        } message: {
            Text(appStore.localized(.performanceModeRestartMessage))
        }
    }

    private var titlesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Button {
                    presentCustomTitlePicker()
                } label: {
                    Label(appStore.localized(.customTitleAddButton), systemImage: "plus")
                }
                Spacer()
            }

            let allEntries = customTitleEntries
            let filtered = filteredCustomTitleEntries

            if allEntries.isEmpty {
                customTitleEmptyState
            } else {
                Text(appStore.localized(.customTitleHint))
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                TextField(
                    "", text: $titleSearch,
                    prompt: Text(appStore.localized(.renameSearchPlaceholder))
                )
                .textFieldStyle(.roundedBorder)

                if filtered.isEmpty {
                    Text(appStore.localized(.customTitleNoResults))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
                } else {
                    VStack(spacing: 12) {
                        ForEach(filtered) { entry in
                            customTitleRow(for: entry)
                        }
                    }
                }
            }
        }
    }

    private var hiddenAppsSection: some View {
        let entries = hiddenAppEntries
        return VStack(alignment: .leading, spacing: 16) {
            HStack {
                Button {
                    presentHiddenAppPicker()
                } label: {
                    Label(appStore.localized(.hiddenAppsAddButton), systemImage: "eye.slash")
                }
                Spacer()
            }

            if entries.isEmpty {
                hiddenAppsEmptyState
            } else {
                Text(appStore.localized(.hiddenAppsHint))
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                TextField(
                    "", text: $hiddenSearch,
                    prompt: Text(appStore.localized(.hiddenAppsSearchPlaceholder))
                )
                .textFieldStyle(.roundedBorder)

                let filtered = filteredHiddenAppEntries
                if filtered.isEmpty {
                    Text(appStore.localized(.customTitleNoResults))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
                } else {
                    VStack(spacing: 12) {
                        ForEach(filtered) { entry in
                            hiddenAppRow(for: entry)
                        }
                    }
                }
            }
        }
    }

    private var hiddenAppEntries: [HiddenAppEntry] {
        appStore.hiddenAppPaths
            .map { path in
                let info = appStore.appInfoForCustomTitle(path: path)
                let defaultName = appStore.defaultDisplayName(for: path)
                return HiddenAppEntry(id: path, appInfo: info, defaultName: defaultName)
            }
            .sorted { lhs, rhs in
                lhs.appInfo.name.localizedCaseInsensitiveCompare(rhs.appInfo.name)
                    == .orderedAscending
            }
    }

    private var filteredHiddenAppEntries: [HiddenAppEntry] {
        let base = hiddenAppEntries
        let trimmed = hiddenSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return base }
        let query = trimmed.lowercased()
        return base.filter { entry in
            if entry.appInfo.name.lowercased().contains(query) { return true }
            if entry.defaultName.lowercased().contains(query) { return true }
            if entry.id.lowercased().contains(query) { return true }
            return false
        }
    }

    private var hiddenAppsEmptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(appStore.localized(.hiddenAppsEmptyTitle))
                .font(.headline)
            Text(appStore.localized(.hiddenAppsEmptySubtitle))
                .font(.footnote)
                .foregroundStyle(.secondary)

            Button {
                presentHiddenAppPicker()
            } label: {
                Label(appStore.localized(.hiddenAppsAddButton), systemImage: "eye.slash")
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlass(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func hiddenAppRow(for entry: HiddenAppEntry) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(nsImage: IconStore.shared.icon(for: entry.appInfo))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 40, height: 40)
                .cornerRadius(10)

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.appInfo.name)
                    .font(.callout.weight(.semibold))
                Text(entry.defaultName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(entry.id)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                appStore.unhideApp(path: entry.id)
            } label: {
                Text(appStore.localized(.hiddenAppsRemoveButton))
            }
            .buttonStyle(.bordered)
        }
        .padding(14)
        .liquidGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private struct HiddenAppEntry: Identifiable {
        let id: String
        let appInfo: AppInfo
        let defaultName: String
    }

    private var customTitleEntries: [CustomTitleEntry] {
        appStore.customTitles
            .map { (path, _) in
                let info = appStore.appInfoForCustomTitle(path: path)
                let defaultName = appStore.defaultDisplayName(for: path)
                return CustomTitleEntry(id: path, appInfo: info, defaultName: defaultName)
            }
            .sorted { lhs, rhs in
                lhs.appInfo.name.localizedCaseInsensitiveCompare(rhs.appInfo.name)
                    == .orderedAscending
            }
    }

    private var filteredCustomTitleEntries: [CustomTitleEntry] {
        let base = customTitleEntries
        let trimmed = titleSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return base }
        let query = trimmed.lowercased()
        return base.filter { entry in
            let custom = entry.appInfo.name.lowercased()
            if custom.contains(query) { return true }
            if entry.defaultName.lowercased().contains(query) { return true }
            if entry.id.lowercased().contains(query) { return true }
            return false
        }
    }

    private var customTitleEmptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(appStore.localized(.customTitleEmptyTitle))
                .font(.headline)
            Text(appStore.localized(.customTitleEmptySubtitle))
                .font(.footnote)
                .foregroundStyle(.secondary)

            Button {
                presentCustomTitlePicker()
            } label: {
                Label(appStore.localized(.customTitleAddButton), systemImage: "plus")
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlass(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    @ViewBuilder
    private func customTitleRow(for entry: CustomTitleEntry) -> some View {
        let isEditing = editingEntries.contains(entry.id)
        let currentDraft =
            editingDrafts[entry.id] ?? appStore.customTitles[entry.id] ?? entry.appInfo.name
        let trimmedDraft = currentDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let originalValue = appStore.customTitles[entry.id] ?? entry.defaultName
        let draftBinding = Binding(
            get: {
                editingDrafts[entry.id] ?? appStore.customTitles[entry.id] ?? entry.appInfo.name
            },
            set: { editingDrafts[entry.id] = $0 }
        )

        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                Image(nsImage: IconStore.shared.icon(for: entry.appInfo))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 40, height: 40)
                    .cornerRadius(10)

                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.appInfo.name)
                        .font(.callout.weight(.semibold))
                    Text(
                        String(
                            format: appStore.localized(.customTitleDefaultFormat), entry.defaultName
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 10) {
                    if isEditing {
                        Button(appStore.localized(.customTitleSave)) {
                            saveCustomTitle(entry)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(trimmedDraft.isEmpty || trimmedDraft == originalValue)

                        Button(appStore.localized(.customTitleCancel)) {
                            cancelEditing(entry)
                        }
                        .buttonStyle(.bordered)

                        if !(appStore.customTitles[entry.id]?.isEmpty ?? true) {
                            Button(role: .destructive) {
                                removeCustomTitle(entry)
                            } label: {
                                Text(appStore.localized(.customTitleDelete))
                            }
                            .buttonStyle(.bordered)
                        }
                    } else {
                        Button(appStore.localized(.customTitleEdit)) {
                            beginEditing(entry)
                        }
                        .buttonStyle(.bordered)

                        if !(appStore.customTitles[entry.id]?.isEmpty ?? true) {
                            Button(role: .destructive) {
                                removeCustomTitle(entry)
                            } label: {
                                Text(appStore.localized(.customTitleDelete))
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }

            if isEditing {
                TextField(
                    "", text: draftBinding,
                    prompt: Text(appStore.localized(.customTitlePlaceholder))
                )
                .textFieldStyle(.roundedBorder)
            }
        }
        .padding(14)
        .liquidGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func presentHiddenAppPicker() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.applicationBundle]
        panel.prompt = appStore.localized(.hiddenAppsAddButton)
        panel.title = appStore.localized(.hiddenAppsAddButton)

        if panel.runModal() == .OK {
            if !appStore.hideApps(at: panel.urls) {
                NSSound.beep()
            }
        }
    }

    private func presentCustomTitlePicker() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.applicationBundle]
        panel.title = appStore.localized(.customTitleAddButton)
        panel.message = appStore.localized(.customTitlePickerMessage)
        panel.prompt = appStore.localized(.chooseButton)

        if panel.runModal() == .OK, let url = panel.url,
            let info = appStore.ensureCustomTitleEntry(for: url)
        {
            let path = info.url.path
            editingEntries.insert(path)
            editingDrafts[path] = appStore.customTitles[path] ?? info.name
        }
    }

    private func presentAppIconPicker() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.icns, .png, .jpeg, .tiff]
        panel.prompt = appStore.localized(.customIconChoose)
        panel.title = appStore.localized(.customIconTitle)

        if panel.runModal() == .OK, let url = panel.url {
            if !appStore.setCustomAppIcon(from: url) {
                iconImportError = appStore.localized(.customIconError)
            }
        }
    }

    private func presentAppSourcePicker() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = appStore.localized(.chooseButton)

        if panel.runModal() == .OK {
            var addedAny = false
            for url in panel.urls {
                if appStore.addCustomAppSource(path: url.path) {
                    addedAny = true
                }
            }
            if !addedAny && !panel.urls.isEmpty {
                NSSound.beep()
            }
        }
    }

    private func pathExists(_ path: String) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
    }

    private func displayName(for path: String) -> String {
        let url = URL(fileURLWithPath: path)
        let name = url.lastPathComponent
        return name.isEmpty ? path : name
    }

    @ViewBuilder
    private func appSourceRow(
        icon: String, path: String, isAvailable: Bool, @ViewBuilder accessory: () -> some View
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .center)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(displayName(for: path))
                        .font(.body)
                    if !isAvailable {
                        Text(appStore.localized(.scanSourcesMissingBadge))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.orange)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.orange.opacity(0.18)))
                    }
                }
                Text(path)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)
            accessory()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
    }

    private struct CustomTitleEntry: Identifiable {
        let id: String
        let appInfo: AppInfo
        let defaultName: String
    }

    private func beginEditing(_ entry: CustomTitleEntry) {
        editingEntries.insert(entry.id)
        editingDrafts[entry.id] = appStore.customTitles[entry.id] ?? entry.appInfo.name
    }

    private func cancelEditing(_ entry: CustomTitleEntry) {
        editingEntries.remove(entry.id)
        editingDrafts.removeValue(forKey: entry.id)
    }

    private func saveCustomTitle(_ entry: CustomTitleEntry) {
        let draft =
            (editingDrafts[entry.id] ?? appStore.customTitles[entry.id] ?? entry.appInfo.name)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !draft.isEmpty else { return }
        let original = appStore.customTitles[entry.id] ?? entry.defaultName
        if draft == original {
            editingEntries.remove(entry.id)
            editingDrafts.removeValue(forKey: entry.id)
            return
        }
        appStore.setCustomTitle(draft, for: entry.appInfo)
        editingEntries.remove(entry.id)
        editingDrafts.removeValue(forKey: entry.id)
    }

    private func removeCustomTitle(_ entry: CustomTitleEntry) {
        appStore.clearCustomTitle(for: entry.appInfo)
        editingEntries.remove(entry.id)
        editingDrafts.removeValue(forKey: entry.id)
    }

    private static let modifierOnlyKeyCodes: Set<UInt16> = [55, 54, 58, 61, 56, 60, 59, 62, 57]

    private func startShortcutCapture(for target: ShortcutTarget) {
        stopShortcutCapture(cancel: false)
        pendingShortcut = nil
        capturingShortcutTarget = target
        shortcutCaptureMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            handleShortcutCapture(event: event)
        }
    }

    private func stopShortcutCapture(cancel: Bool) {
        if let monitor = shortcutCaptureMonitor {
            NSEvent.removeMonitor(monitor)
            shortcutCaptureMonitor = nil
        }
        if cancel {
            pendingShortcut = nil
            if capturingShortcutTarget != nil { NSSound.beep() }
        }
        capturingShortcutTarget = nil
    }

    private func handleShortcutCapture(event: NSEvent) -> NSEvent? {
        let normalizedFlags = event.modifierFlags.normalizedShortcutFlags

        if event.keyCode == 53 && normalizedFlags.isEmpty {
            stopShortcutCapture(cancel: true)
            return nil
        }

        guard !normalizedFlags.isEmpty, !Self.modifierOnlyKeyCodes.contains(event.keyCode) else {
            NSSound.beep()
            return nil
        }

        pendingShortcut = AppStore.HotKeyConfiguration(
            keyCode: event.keyCode, modifierFlags: normalizedFlags)
        return nil
    }

    private func savePendingShortcut() {
        guard let shortcut = pendingShortcut, let target = capturingShortcutTarget else { return }
        switch target {
        case .launchpad:
            appStore.setGlobalHotKey(
                keyCode: shortcut.keyCode, modifierFlags: shortcut.modifierFlags)
        // case .aiOverlay:
        //     appStore.setAIOverlayHotKey(keyCode: shortcut.keyCode, modifierFlags: shortcut.modifierFlags)
        }
        pendingShortcut = nil
        stopShortcutCapture(cancel: false)
    }

    private func shortcutStatusText(for target: ShortcutTarget) -> String {
        if capturingShortcutTarget == target {
            if let shortcut = pendingShortcut {
                let base = shortcut.displayString
                if shortcut.modifierFlags.isEmpty {
                    return base + " • " + appStore.localized(.shortcutNoModifierWarning)
                }
                return base
            }
            return appStore.localized(.shortcutCapturePrompt)
        }
        let placeholder = appStore.localized(.shortcutNotSet)
        switch target {
        case .launchpad:
            return appStore.hotKeyDisplayText(nonePlaceholder: placeholder)
        // case .aiOverlay:
        //     return appStore.aiOverlayHotKeyDisplayText(nonePlaceholder: placeholder)
        }
    }

    private func isCapturingShortcut(_ target: ShortcutTarget) -> Bool {
        capturingShortcutTarget == target
    }

    @ViewBuilder
    private var headlineGlass: some View {
        PressableGlassTitle(text: appStore.localized(.appTitle))
    }

    private struct PressableGlassTitle: View {
        let text: String

        @GestureState private var isPressed = false
        @State private var bounce = false

        private var scale: CGFloat {
            if isPressed { return 0.97 }
            if bounce { return 1.01 }
            return 1.0
        }

        private var shadowOpacity: Double {
            isPressed ? 0.18 : 0.0
        }

        private var shadowRadius: CGFloat {
            isPressed ? 8 : 0
        }

        private var shadowOffsetY: CGFloat {
            isPressed ? 4 : 0
        }

        var body: some View {
            let label = Text(text)
                .font(.largeTitle.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)

            label
                .glassEffect(.clear, in: Capsule())
                .clipShape(Capsule())
                .shadow(
                    color: Color.black.opacity(shadowOpacity), radius: shadowRadius, x: 0,
                    y: shadowOffsetY
                )
                .scaleEffect(scale)
                .contentShape(Capsule())
                .gesture(pressGesture)
                .animation(.easeOut(duration: 0.12), value: isPressed)
                .animation(.spring(response: 0.26, dampingFraction: 0.62), value: bounce)
        }

        private var pressGesture: some Gesture {
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if bounce { bounce = false }
                }
                .updating($isPressed) { _, state, _ in
                    state = true
                }
                .onEnded { _ in
                    bounce = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                        bounce = false
                    }
                }
        }
    }

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            ZStack(alignment: .center) {
                Image("AboutBackground")
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(16.0 / 9.0, contentMode: .fill)
                    .frame(maxWidth: .infinity)
                    .clipped()

                VStack(spacing: 12) {
                    headlineGlass

                    Text(
                        String(
                            format: appStore.localized(.versionLabelFormat),
                            getVersion(fallback: appStore.localized(.versionFallback)))
                    )
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)

                    Text(appStore.localized(.backgroundHint))
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.85))
                }
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 180, maxHeight: 200)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 1.4)
            )
            .padding(.bottom, 12)

            HStack(alignment: .bottom, spacing: 12) {
                TicTacToeBoard()
                    .frame(width: 130)

                infoCard
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, minHeight: 550, alignment: .top)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private var infoCard: some View {
        let cardFill = colorScheme == .light ? Color.white : Color.white.opacity(0.05)
        VStack(alignment: .leading, spacing: 10) {
            Text(appStore.localized(.aboutInfoSystemTitle))
                .font(.headline.weight(.semibold))
            infoRow(label: appStore.localized(.aboutInfoMacOSLabel), value: systemVersionText)

            Divider()

            Text(appStore.localized(.aboutInfoProcessorTitle))
                .font(.headline.weight(.semibold))
            infoRow(label: appStore.localized(.aboutInfoChipLabel), value: chipText)

            Divider()

            Text(appStore.localized(.aboutInfoDisplayTitle))
                .font(.headline.weight(.semibold))
            infoRow(label: displayNameText, value: displayResolutionText)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(cardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.primary)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
        .font(.subheadline)
    }

    @ViewBuilder
    private func glassButton(title: String, systemImage: String, action: @escaping () -> Void)
        -> some View
    {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    // MARK: - Inline Games
    private struct TicTacToeBoard: View {
        private enum Mark: String {
            case x = "X"
            case o = "O"
            case empty = ""
        }

        @State private var cells: [Mark] = Array(repeating: .empty, count: 9)
        @State private var isPlayerTurn: Bool = true
        @State private var statusText: String = "Your turn"
        @State private var gameOver: Bool = false

        var body: some View {
            VStack(spacing: 12) {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3),
                    spacing: 6
                ) {
                    ForEach(0..<9) { index in
                        ZStack {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.secondary.opacity(0.12))
                            Text(cells[index].rawValue)
                                .font(.system(size: 28, weight: .bold))
                        }
                        .aspectRatio(1, contentMode: .fit)
                        .onTapGesture {
                            guard !gameOver, isPlayerTurn, cells[index] == .empty else { return }
                            makeMove(at: index, mark: .x)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                aiTurn()
                            }
                        }
                    }
                }
                Text(statusText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Button(action: resetGame) {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.bordered)
            }
        }

        private func makeMove(at index: Int, mark: Mark) {
            cells[index] = mark
            if let winner = evaluateWinner() {
                statusText = winner == .x ? "You win!" : "AI wins!"
                gameOver = true
            } else if !cells.contains(.empty) {
                statusText = "Draw"
                gameOver = true
            } else {
                isPlayerTurn.toggle()
                statusText = isPlayerTurn ? "Your turn" : "AI thinking..."
            }
        }

        private func aiTurn() {
            guard !gameOver else { return }
            guard !isPlayerTurn else { return }

            let emptyCells = cells.enumerated().filter { $0.element == .empty }.map { $0.offset }
            guard let choice = emptyCells.randomElement() else { return }
            makeMove(at: choice, mark: .o)
        }

        private func evaluateWinner() -> Mark? {
            let lines = [
                [0, 1, 2], [3, 4, 5], [6, 7, 8],
                [0, 3, 6], [1, 4, 7], [2, 5, 8],
                [0, 4, 8], [2, 4, 6],
            ]
            for line in lines {
                let marks = line.map { cells[$0] }
                if marks.allSatisfy({ $0 == .x }) { return .x }
                if marks.allSatisfy({ $0 == .o }) { return .o }
            }
            return nil
        }

        private func resetGame() {
            cells = Array(repeating: .empty, count: 9)
            isPlayerTurn = true
            statusText = "Your turn"
            gameOver = false
        }
    }

    private func currentMemoryUsageValue() -> String {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size) / 4
        let kern = withUnsafeMutablePointer(to: &info) { pointer -> kern_return_t in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }

        guard kern == KERN_SUCCESS else { return "--" }

        let usedBytes = info.phys_footprint
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .memory
        return formatter.string(fromByteCount: Int64(usedBytes))
    }

    private func currentMemoryUsageString() -> String {
        "Memory: \(currentMemoryUsageValue())"
    }

    private func formattedCacheUpdate(_ date: Date) -> String {
        if date == .distantPast {
            return appStore.localized(.performanceCacheNever)
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func performanceModePicker() -> some View {
        HStack(spacing: 6) {
            performanceModeButton(mode: .lean, title: appStore.localized(.performanceModeLean))
            performanceModeButton(mode: .full, title: appStore.localized(.performanceModeFull))
        }
        .padding(6)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .quaternarySystemFill))
        )
    }

    private func performanceModeButton(mode: PerformanceMode, title: String) -> some View {
        let isSelected = appStore.performanceMode == mode
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                appStore.performanceMode = mode
            }
        } label: {
            Text(title)
                .font(.callout.weight(.semibold))
                .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(
                    Capsule(style: .continuous)
                        .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(
                            isSelected ? Color.accentColor.opacity(0.45) : Color.clear, lineWidth: 1
                        )
                )
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }

    private func cacheStatusBadge(isValid: Bool) -> some View {
        let title = appStore.localized(
            isValid ? .performanceCacheStatusValid : .performanceCacheStatusInvalid)
        let color = isValid ? Color.green : Color.orange
        return Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(color.opacity(0.16))
            )
    }

    private func leanModeBadge() -> some View {
        Text(appStore.localized(.performanceModeLean))
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Color.green)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.green.opacity(0.16))
            )
    }

    private func cacheCountRow(title: String, valueText: String) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
            Text(valueText)
                .font(.callout.weight(.semibold).monospacedDigit())
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .quaternarySystemFill))
        )
    }

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            appearanceModeCard

            loginLayoutCard
                .padding(.top, -10)

            Text(appStore.localized(.lockLayoutDescription))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.top, -20)

            applicationIconCard
                .padding(.top, -15)

            // Data Management 已移除以符合 App Store 审核指南

            HStack {
                Button {
                    appStore.refresh()
                } label: {
                    Label(appStore.localized(.refresh), systemImage: "arrow.clockwise")
                }
                Spacer()
                Button {
                    showResetConfirm = true
                } label: {
                    Label(appStore.localized(.resetLayout), systemImage: "arrow.counterclockwise")
                        .foregroundStyle(Color.red)
                }
                .alert(appStore.localized(.resetAlertTitle), isPresented: $showResetConfirm) {
                    Button(appStore.localized(.resetConfirm), role: .destructive) {
                        appStore.resetLayout()
                    }
                    Button(appStore.localized(.cancel), role: .cancel) {}
                } message: {
                    Text(appStore.localized(.resetAlertMessage))
                }
                Button {
                    AppDelegate.shared?.quitWithFade()
                } label: {
                    Label(appStore.localized(.quit), systemImage: "xmark.circle")
                        .foregroundStyle(Color.red)
                }
            }
        }
    }

    private var loginLayoutCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(appStore.localized(.launchAtLoginTitle))
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Toggle("", isOn: $appStore.isStartOnLogin)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(!appStore.canConfigureStartOnLogin)
            }

            Divider()

            HStack(alignment: .center, spacing: 24) {
                HStack {
                    Text(appStore.localized(.lockLayoutTitle))
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Toggle("", isOn: $appStore.isLayoutLocked)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack {
                    Text(appStore.localized(.showQuickRefreshButton))
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Toggle("", isOn: $appStore.showQuickRefreshButton)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
    }

    private var applicationIconCard: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(appStore.localized(.customIconTitle))
                    .font(.headline)
                let hint = appStore.localized(.customIconHint)
                Text(twoLineHint(hint))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .trailing, spacing: 8) {
                    Button {
                        presentAppIconPicker()
                    } label: {
                        Label(
                            appStore.localized(.customIconChoose), systemImage: "checkmark.circle")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        appStore.resetCustomAppIcon()
                    } label: {
                        Label(
                            appStore.localized(.customIconReset),
                            systemImage: "arrow.counterclockwise")
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .disabled(!appStore.hasCustomAppIcon)
                }

                Image(nsImage: appStore.currentAppIcon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 66, height: 66)
                    .cornerRadius(12)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
    }

    // dataManagementCard 已移除以符合 App Store 审核指南

    private func twoLineHint(_ text: String) -> String {
        let separators = [". ", "。", "！", "？", "；", ";", "，", ",", "、"]
        for sep in separators {
            if let range = text.range(of: sep) {
                let before = text[..<range.upperBound]
                let after = text[range.upperBound...].trimmingCharacters(in: .whitespaces)
                if after.isEmpty {
                    return String(before)
                }
                return String(before) + "\n" + after
            }
        }

        let words = text.split(separator: " ")
        if words.count >= 2 {
            let mid = words.count / 2
            let first = words[..<mid].joined(separator: " ")
            let second = words[mid...].joined(separator: " ")
            return first + "\n" + second
        }

        return text
    }

    @ViewBuilder
    private var appearanceModeCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Text(appStore.localized(.appearanceModeTitle))
                    .font(.headline)
                    .frame(minWidth: 90, alignment: .leading)

                Spacer(minLength: 8)

                HStack(spacing: 16) {
                    appearanceOptionCard(
                        title: appStore.localized(.appearanceModeFollowSystem),
                        imageName: "AppearanceAuto",
                        mode: .system
                    )
                    appearanceOptionCard(
                        title: appStore.localized(.appearanceModeLight),
                        imageName: "AppearanceLight",
                        mode: .light
                    )
                    appearanceOptionCard(
                        title: appStore.localized(.appearanceModeDark),
                        imageName: "AppearanceDark",
                        mode: .dark
                    )
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }

            Divider()

            languageRow
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
    }

    private func appearanceOptionCard(title: String, imageName: String, mode: AppearancePreference)
        -> some View
    {
        let isSelected = appStore.appearancePreference == mode
        return Button {
            appStore.appearancePreference = mode
        } label: {
            VStack(spacing: 2) {
                Image(imageName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .stroke(
                                isSelected ? Color.accentColor : Color.primary.opacity(0.08),
                                lineWidth: isSelected ? 2 : 1)
                    )
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
            }
            .frame(minWidth: 52, alignment: .leading)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var languageRow: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(appStore.localized(.languagePickerTitle))
                .font(.headline)
                .frame(minWidth: 90, alignment: .leading)
            Spacer()
            Picker("", selection: $appStore.preferredLanguage) {
                ForEach(AppLanguage.allCases) { language in
                    Text(appStore.localizedLanguageName(for: language)).tag(language)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 180, alignment: .trailing)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var appSourcesSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text(appStore.localized(.scanSourcesIntroTitle))
                    .font(.headline)
                Text(appStore.localized(.scanSourcesIntroDescription))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 12) {
                Text(appStore.localized(.scanSourcesDefaultListTitle))
                    .font(.subheadline.weight(.semibold))
                ForEach(appStore.builtinAppSourcePaths, id: \.self) { path in
                    appSourceRow(
                        icon: "internaldrive", path: path, isAvailable: true,
                        accessory: { EmptyView() })
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Text(appStore.localized(.scanSourcesCustomListTitle))
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Button {
                        presentAppSourcePicker()
                    } label: {
                        Label(appStore.localized(.scanSourcesAddButton), systemImage: "plus.circle")
                    }
                    .buttonStyle(.borderless)

                    Button {
                        showAppSourcesResetDialog = true
                    } label: {
                        Label(
                            appStore.localized(.scanSourcesResetButton),
                            systemImage: "arrow.counterclockwise")
                    }
                    .buttonStyle(.borderless)
                    .disabled(appStore.customAppSourcePaths.isEmpty)
                }

                if appStore.customAppSourcePaths.isEmpty {
                    Text(appStore.localized(.scanSourcesEmptyHint))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                } else {
                    ForEach(appStore.customAppSourcePaths, id: \.self) { path in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                appSourceRow(
                                    icon: "folder", path: path, isAvailable: pathExists(path)
                                ) {
                                    HStack(spacing: 10) {
                                        Button {
                                            toggleExpandedSource(path)
                                        } label: {
                                            // Image(systemName: expandedSource == standardizePath(path) ? "chevron.down.circle" : "chevron.right.circle")
                                            //     .foregroundStyle(.secondary)
                                            Image(systemName: "ellipsis.circle")
                                                .foregroundStyle(.secondary)
                                        }
                                        .buttonStyle(.borderless)

                                        Button {
                                            appStore.removeCustomAppSource(path: path)
                                        } label: {
                                            Image(systemName: "minus.circle.fill")
                                                .foregroundStyle(Color.red)
                                        }
                                        .buttonStyle(.borderless)
                                    }
                                }
                            }

                            if expandedSource == standardizePath(path) {
                                let apps = appsForSource(path)
                                VStack(alignment: .leading, spacing: 8) {
                                    if apps.isEmpty {
                                        Text(appStore.localized(.scanSourcesEmptyHint))
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                            .padding(.horizontal, 4)
                                    } else {
                                        ScrollView {
                                            LazyVStack(alignment: .leading, spacing: 8) {
                                                ForEach(apps, id: \.path) { app in
                                                    HStack(spacing: 8) {
                                                        Image(nsImage: app.icon)
                                                            .resizable()
                                                            .interpolation(.high)
                                                            .antialiased(true)
                                                            .frame(width: 24, height: 24)
                                                            .cornerRadius(5)
                                                        VStack(alignment: .leading, spacing: 2) {
                                                            Text(app.name)
                                                                .font(.callout)
                                                                .lineLimit(1)
                                                            Text(app.path)
                                                                .font(.caption2)
                                                                .foregroundStyle(.secondary)
                                                                .lineLimit(1)
                                                        }
                                                        Spacer()
                                                        Button(role: .destructive) {
                                                            removeAppFromLayout(app.path)
                                                        } label: {
                                                            Image(systemName: "trash")
                                                                .foregroundStyle(Color.red)
                                                        }
                                                        .buttonStyle(.borderless)
                                                    }
                                                    .padding(.horizontal, 6)
                                                }
                                            }
                                            .padding(.vertical, 6)
                                        }
                                        .frame(maxHeight: 220)
                                    }
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(Color.secondary.opacity(0.08))
                                )
                            }
                        }
                    }
                }
            }
        }
        .confirmationDialog(
            appStore.localized(.scanSourcesResetButton), isPresented: $showAppSourcesResetDialog,
            titleVisibility: .visible
        ) {
            Button(appStore.localized(.scanSourcesResetButton), role: .destructive) {
                appStore.resetCustomAppSources()
            }
            Button(appStore.localized(.cancel), role: .cancel) {}
        }
    }

    // MARK: - Helpers
    private struct SourceApp {
        let name: String
        let path: String
        let icon: NSImage
    }

    private func appsForSource(_ sourcePath: String) -> [SourceApp] {
        let normalizedSource = standardizePath(sourcePath)
        let prefix = normalizedSource.hasSuffix("/") ? normalizedSource : normalizedSource + "/"
        var apps: [SourceApp] = []
        var seen: Set<String> = []

        func consider(name: String, path: String, icon: NSImage) {
            let normalized = standardizePath(path)
            guard normalized == normalizedSource || normalized.hasPrefix(prefix) else { return }
            if seen.insert(normalized).inserted {
                apps.append(SourceApp(name: name, path: normalized, icon: icon))
            }
        }

        for item in appStore.items {
            switch item {
            case .app(let app):
                consider(name: app.name, path: app.url.path, icon: IconStore.shared.icon(for: app))
            case .missingApp(let placeholder):
                consider(
                    name: placeholder.displayName, path: placeholder.bundlePath,
                    icon: placeholder.icon)
            case .folder(let folder):
                for app in folder.apps {
                    consider(
                        name: app.name, path: app.url.path, icon: IconStore.shared.icon(for: app))
                }
            case .empty:
                break
            }
        }

        return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func standardizePath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardized.path
    }

    @State private var expandedSource: String? = nil

    private func toggleExpandedSource(_ path: String) {
        withAnimation(.easeInOut(duration: 0.2)) {
            let normalized = standardizePath(path)
            expandedSource = (expandedSource == normalized) ? nil : normalized
        }
    }

    private func removeAppFromLayout(_ rawPath: String) {
        let normalized = standardizePath(rawPath)
        // Replace matching top-level items with empty placeholders.
        var updatedItems = appStore.items
        for idx in updatedItems.indices {
            switch updatedItems[idx] {
            case .app(let app) where standardizePath(app.url.path) == normalized:
                updatedItems[idx] = .empty(UUID().uuidString)
            case .missingApp(let placeholder)
            where standardizePath(placeholder.bundlePath) == normalized:
                updatedItems[idx] = .empty(UUID().uuidString)
            case .folder(var folder):
                let originalCount = folder.apps.count
                folder.apps.removeAll { standardizePath($0.url.path) == normalized }
                if folder.apps.count != originalCount {
                    if folder.apps.isEmpty {
                        updatedItems[idx] = .empty(UUID().uuidString)
                    } else {
                        updatedItems[idx] = .folder(folder)
                    }
                }
            default:
                break
            }
        }
        appStore.items = updatedItems

        // Sync cleanup in the folders list.
        for idx in appStore.folders.indices {
            appStore.folders[idx].apps.removeAll { standardizePath($0.url.path) == normalized }
        }
        // Cleanup in the apps list.
        appStore.apps.removeAll { standardizePath($0.url.path) == normalized }

        appStore.compactItemsWithinPages()
        appStore.removeEmptyPages()
        appStore.folderUpdateTrigger = UUID()
        appStore.gridRefreshTrigger = UUID()
        appStore.saveAllOrder()
    }

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(appStore.localized(.classicMode))
                    Spacer()
                    Toggle("", isOn: $appStore.isFullscreenMode)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }

                HStack {
                    Text(appStore.localized(.showLabels))
                    Spacer()
                    Toggle("", isOn: $appStore.showLabels)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }

                HStack {
                    Text(appStore.localized(.useLocalizedThirdPartyTitles))
                    Spacer()
                    Toggle("", isOn: $appStore.useLocalizedThirdPartyTitles)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }

                HStack {
                    Text(appStore.localized(.predictDrop))
                    Spacer()
                    Toggle("", isOn: $appStore.enableDropPrediction)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
                HStack {
                    Text(appStore.localized(.enableAnimations))
                    Spacer()
                    Toggle("", isOn: $appStore.enableAnimations)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }

                HStack {
                    Text(appStore.localized(.followScrollPagingTitle))
                    Spacer()
                    Toggle("", isOn: $appStore.followScrollPagingEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }

                HStack {
                    Text(appStore.localized(.hideDockOption))
                    Spacer()
                    Toggle("", isOn: $appStore.hideDock)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }

                HStack {
                    Text(appStore.localized(.rememberPageTitle))
                    Spacer()
                    Toggle("", isOn: $appStore.rememberLastPage)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }

                HStack {
                    Text(appStore.localized(.hoverMagnification))
                    Spacer()
                    Toggle("", isOn: $appStore.enableHoverMagnification)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }

                HStack {
                    Text(appStore.localized(.activePressEffect))
                    Spacer()
                    Toggle("", isOn: $appStore.enableActivePressEffect)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(appStore.localized(.backgroundStyleTitle))
                        .font(.headline)
                    Picker("", selection: $appStore.launchpadBackgroundStyle) {
                        ForEach(AppStore.BackgroundStyle.allCases) { style in
                            Text(appStore.localized(style.localizationKey)).tag(style)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

            }

            Divider()

            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(appStore.localized(.animationDurationLabel))
                        .font(.headline)
                    Slider(value: $appStore.animationDuration, in: 0.1...1.0, step: 0.05)
                        .disabled(!appStore.enableAnimations)
                    HStack {
                        Text("0.1s").font(.footnote)
                        Spacer()
                        Text(String(format: "%.2fs", appStore.animationDuration))
                            .font(.footnote)
                        Spacer()
                        Text("1.0s").font(.footnote)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(appStore.localized(.iconLabelFontWeight))
                        .font(.headline)
                    Picker("", selection: $appStore.iconLabelFontWeight) {
                        ForEach(AppStore.IconLabelFontWeightOption.allCases) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(appStore.localized(.sidebarIconSizeTitle))
                        .font(.headline)
                    Picker("", selection: $appStore.sidebarIconPreset) {
                        Text(appStore.localized(.sidebarIconSizeLarge)).tag(
                            AppStore.SidebarIconPreset.large)
                        Text(appStore.localized(.sidebarIconSizeMedium)).tag(
                            AppStore.SidebarIconPreset.medium)
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(appStore.localized(.iconSize))
                        .font(.headline)
                    Slider(value: $appStore.iconScale, in: 0.8...1.1)
                    HStack {
                        Text(appStore.localized(.smaller)).font(.footnote)
                        Spacer()
                        Text(appStore.localized(.larger)).font(.footnote)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(appStore.localized(.folderWindowWidth))
                            .font(.headline)
                        Spacer()
                        Text(String(format: "%.0f%%", appStore.folderPopoverWidthFactor * 100))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Slider(
                        value: $appStore.folderPopoverWidthFactor,
                        in: AppStore.folderPopoverWidthRange
                    )
                    .disabled(appStore.isFullscreenMode)
                    HStack {
                        Text(
                            String(
                                format: "%.0f%%", AppStore.folderPopoverWidthRange.lowerBound * 100)
                        )
                        .font(.footnote)
                        Spacer()
                        Text(
                            String(
                                format: "%.0f%%", AppStore.folderPopoverWidthRange.upperBound * 100)
                        )
                        .font(.footnote)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(appStore.localized(.folderWindowHeight))
                            .font(.headline)
                        Spacer()
                        Text(String(format: "%.0f%%", appStore.folderPopoverHeightFactor * 100))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Slider(
                        value: $appStore.folderPopoverHeightFactor,
                        in: AppStore.folderPopoverHeightRange
                    )
                    .disabled(appStore.isFullscreenMode)
                    HStack {
                        Text(
                            String(
                                format: "%.0f%%", AppStore.folderPopoverHeightRange.lowerBound * 100
                            )
                        )
                        .font(.footnote)
                        Spacer()
                        Text(
                            String(
                                format: "%.0f%%", AppStore.folderPopoverHeightRange.upperBound * 100
                            )
                        )
                        .font(.footnote)
                    }
                }

                Text(appStore.localized(.folderWindowSizeHint))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 8) {
                    Text(appStore.localized(.hoverMagnificationScale))
                        .font(.headline)
                    Slider(
                        value: $appStore.hoverMagnificationScale,
                        in: AppStore.hoverMagnificationRange
                    )
                    .disabled(!appStore.enableHoverMagnification)
                    HStack {
                        Text(String(format: "%.2fx", AppStore.hoverMagnificationRange.lowerBound))
                            .font(.footnote)
                        Spacer()
                        Text(String(format: "%.2fx", appStore.hoverMagnificationScale))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(String(format: "%.2fx", AppStore.hoverMagnificationRange.upperBound))
                            .font(.footnote)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(appStore.localized(.activePressScale))
                        .font(.headline)
                    Slider(
                        value: $appStore.activePressScale,
                        in: AppStore.activePressScaleRange
                    )
                    .disabled(!appStore.enableActivePressEffect)
                    HStack {
                        Text(String(format: "%.2fx", AppStore.activePressScaleRange.lowerBound))
                            .font(.footnote)
                        Spacer()
                        Text(String(format: "%.2fx", appStore.activePressScale))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(String(format: "%.2fx", AppStore.activePressScaleRange.upperBound))
                            .font(.footnote)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(appStore.localized(.iconsPerRow))
                            .font(.headline)
                        Spacer()
                        Stepper(value: $appStore.gridColumnsPerPage, in: AppStore.gridColumnRange) {
                            Text("\(appStore.gridColumnsPerPage)")
                                .font(.callout.monospacedDigit())
                        }
                        .controlSize(.small)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(appStore.localized(.rowsPerPage))
                            .font(.headline)
                        Spacer()
                        Stepper(value: $appStore.gridRowsPerPage, in: AppStore.gridRowRange) {
                            Text("\(appStore.gridRowsPerPage)")
                                .font(.callout.monospacedDigit())
                        }
                        .controlSize(.small)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(appStore.localized(.iconHorizontalSpacing))
                            .font(.headline)
                        Spacer()
                        Text("\(Int(appStore.iconColumnSpacing)) pt")
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Slider(
                        value: $appStore.iconColumnSpacing,
                        in: AppStore.columnSpacingRange,
                        step: 1)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(appStore.localized(.iconVerticalSpacing))
                            .font(.headline)
                        Spacer()
                        Text("\(Int(appStore.iconRowSpacing)) pt")
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Slider(
                        value: $appStore.iconRowSpacing,
                        in: AppStore.rowSpacingRange,
                        step: 1)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(appStore.localized(.gridSizeChangeWarning))
                    Text(appStore.localized(.pageIndicatorHint))
                        .foregroundStyle(.tertiary)
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.top, 2)

                VStack(alignment: .leading, spacing: 8) {
                    Text(appStore.localized(.globalShortcutTitle))
                        .font(.headline)
                    HStack(spacing: 12) {
                        Button {
                            if isCapturingShortcut(.launchpad) {
                                stopShortcutCapture(cancel: true)
                            } else {
                                startShortcutCapture(for: .launchpad)
                            }
                        } label: {
                            Text(
                                isCapturingShortcut(.launchpad)
                                    ? appStore.localized(.cancel)
                                    : appStore.localized(.shortcutSetButton))
                        }

                        Button(appStore.localized(.shortcutSaveButton)) {
                            savePendingShortcut()
                        }
                        .disabled(!(isCapturingShortcut(.launchpad) && pendingShortcut != nil))

                        Button(appStore.localized(.shortcutClearButton)) {
                            if isCapturingShortcut(.launchpad) {
                                stopShortcutCapture(cancel: false)
                                pendingShortcut = nil
                            }
                            appStore.clearGlobalHotKey()
                        }
                        .disabled(!isCapturingShortcut(.launchpad) && appStore.globalHotKey == nil)
                    }

                    Text(shortcutStatusText(for: .launchpad))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(appStore.localized(.labelFontSize))
                        .font(.headline)
                    Slider(value: $appStore.iconLabelFontSize, in: 9...16, step: 0.5)
                    HStack {
                        Text("9pt").font(.footnote)
                        Spacer()
                        Text("16pt").font(.footnote)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(appStore.localized(.scrollSensitivity))
                        .font(.headline)
                    Slider(value: $appStore.scrollSensitivity, in: 0.01...0.99)
                    HStack {
                        Text(appStore.localized(.low)).font(.footnote)
                        Spacer()
                        Text(appStore.localized(.high)).font(.footnote)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(
                        String(
                            format: appStore.localized(.folderDropZoneSizeWithDefault),
                            AppStore.defaultFolderDropZoneScale))
                    Slider(
                        value: $appStore.folderDropZoneScale,
                        in: AppStore.folderDropZoneScaleRange,
                        step: 0.05)
                    HStack {
                        Text(String(format: "%.1fx", AppStore.folderDropZoneScaleRange.lowerBound))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(String(format: "%.2fx", appStore.folderDropZoneScale))
                            .font(.footnote.monospacedDigit())
                        Spacer()
                        Text(String(format: "%.1fx", AppStore.folderDropZoneScaleRange.upperBound))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Text(appStore.localized(.folderDropZoneSizeHint))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text(appStore.localized(.pageIndicatorOffsetLabel))
                        .font(.headline)
                    Slider(value: $appStore.pageIndicatorOffset, in: 0...80)
                    HStack {
                        Text("0").font(.footnote)
                        Spacer()
                        Text(String(format: "%.0f", appStore.pageIndicatorOffset)).font(.footnote)
                        Spacer()
                        Text("80").font(.footnote)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(appStore.localized(.pageIndicatorTopPaddingLabel))
                        .font(.headline)
                    Slider(
                        value: $appStore.pageIndicatorTopPadding,
                        in: AppStore.pageIndicatorTopPaddingRange)
                    HStack {
                        Text(
                            String(format: "%.0f", AppStore.pageIndicatorTopPaddingRange.lowerBound)
                        ).font(.footnote)
                        Spacer()
                        Text(String(format: "%.0f", appStore.pageIndicatorTopPadding)).font(
                            .footnote)
                        Spacer()
                        Text(
                            String(format: "%.0f", AppStore.pageIndicatorTopPaddingRange.upperBound)
                        ).font(.footnote)
                    }
                }

            }
        }
    }

    // MARK: - Export / Import Application Support Data
    private func supportDirectoryURL() throws -> URL {
        let fm = FileManager.default
        let appSupport = try fm.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil,
            create: true)
        let dir = appSupport.appendingPathComponent("LaunchNext", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    // exportDataFolder, importDataFolder 及相关函数已移除 - Backup 功能已移除

    // MARK: - Preferences export/import (保留用于内部使用)
    private var currentPrefsDomain: String {
        Bundle.main.bundleIdentifier ?? "LaunchNextAppStore"
    }

    // 已移除 importFromLaunchpad() 和 importLegacyArchive() 函数
    // 这些功能访问私有系统数据库，违反 App Store 审核指南 2.5.2

    // MARK: - 已移除的更新检查部分（App Store 合规）
    // updatesSection 已被移除 - App Store 版本使用内置更新机制
    private var updatesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(appStore.localized(.updatesHeroUpToDate))
                .font(.headline)
            Text("App Store 版本使用内置更新机制")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var updatesStatusCard: some View {
        EmptyView()
    }

    private var updatesControlCard: some View {
        EmptyView()
    }

    private func updateControlButton(
        title: String, systemImage: String, isPrimary: Bool = false, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .frame(minWidth: 160)
        }
        .buttonStyle(.plain)
        .background(
            Capsule()
                .fill(
                    isPrimary
                        ? Color.accentColor.opacity(0.16) : Color(nsColor: .windowBackgroundColor))
        )
        .overlay(
            Capsule()
                .stroke(
                    isPrimary ? Color.accentColor.opacity(0.6) : Color.primary.opacity(0.08),
                    lineWidth: 1)
        )
    }

    private var updatesHero: some View {
        EmptyView()
    }
}
