import SwiftUI
import ServiceManagement
import UserNotifications

struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    enum Tab: String, CaseIterable, Identifiable {
        case general, popover, menubar, thresholds, about
        var id: String { rawValue }
        var label: String {
            switch self {
            case .general:    return L("General")
            case .popover:    return L("Popover")
            case .menubar:    return L("Menu Bar")
            case .thresholds: return L("Thresholds")
            case .about:      return L("About")
            }
        }
        var icon: String {
            switch self {
            case .general:    return "gearshape"
            case .popover:    return "square.stack"
            case .menubar:    return "menubar.rectangle"
            case .thresholds: return "gauge.with.needle"
            case .about:      return "info.circle"
            }
        }
    }

    @State private var selectedTab: Tab = .general

    var body: some View {
        NavigationSplitView {
            List(Tab.allCases, selection: $selectedTab) { tab in
                Label(tab.label, systemImage: tab.icon).tag(tab)
            }
            .navigationSplitViewColumnWidth(150)
        } detail: {
            Group {
                switch selectedTab {
                case .general: GeneralSettingsView()
                case .popover: PopoverSettingsView()
                case .menubar: MenubarSettingsView()
                case .thresholds: ThresholdSettingsView()
                case .about: AboutSettingsView()
                }
            }
            .frame(minWidth: 420)
            .navigationTitle(selectedTab.label)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .frame(width: 620, height: 560)
    }
}

// MARK: - General

struct GeneralSettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @State private var loginItemStatus: String = ""

    var body: some View {
        Form {
            Section {
                Picker("Popover refresh", selection: $settings.refreshRate) {
                    ForEach(RefreshRate.allCases) { rate in
                        Text(rate.label).tag(rate)
                    }
                }
                .pickerStyle(.menu)
                Picker("Menubar refresh", selection: $settings.menubarRefreshRate) {
                    ForEach(RefreshRate.allCases) { rate in
                        Text(rate.label).tag(rate)
                    }
                }
                .pickerStyle(.menu)
            } header: {
                Text("Performance")
            } footer: {
                Text("Popover refresh applies when the panel is open. Menubar refresh runs in the background — 10s is recommended to save battery.")
                    .foregroundStyle(.secondary)
            }

            Section("Appearance") {
                Picker("Theme", selection: $settings.theme) {
                    ForEach(AppTheme.allCases) { theme in
                        Text(theme.label).tag(theme)
                    }
                }
                .pickerStyle(.segmented)
                Picker("Language", selection: $settings.language) {
                    ForEach(AppLanguage.allCases) { lang in
                        Text(lang.label).tag(lang)
                    }
                }
                .pickerStyle(.menu)
            }

            Section {
                HStack {
                    Toggle("Launch at login", isOn: $settings.launchAtLogin)
                        .onChange(of: settings.launchAtLogin) { _, newValue in
                            applyLaunchAtLogin(newValue)
                        }
                    Spacer()
                    if !loginItemStatus.isEmpty {
                        Text(loginItemStatus).font(.caption).foregroundStyle(.secondary)
                    }
                }
                HStack {
                    Toggle("Global hotkey ⌥Space", isOn: $settings.globalHotkeyEnabled)
                    Spacer()
                    Text("Requires Accessibility access").font(.caption).foregroundStyle(.secondary)
                }
            } header: {
                Text("System")
            }

            Section {
                HStack {
                    Text("Version")
                    Spacer()
                    Text(UpdateChecker.shared.currentVersion)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Toggle("Check for updates automatically", isOn: $settings.autoUpdateCheck)
                Button("Check for updates now") {
                    UpdateChecker.shared.checkNow()
                }
            } header: {
                Text("Updates")
            }

            Section {
                Toggle(isOn: $settings.moodFaceEnabled) {
                    HStack(spacing: 6) {
                        Text("MoodFace")
                        Text("😊😤💀")
                    }
                }
                if settings.moodFaceEnabled {
                    MoodPreviewRow()
                }
            } header: {
                Text("MoodFace")
            } footer: {
                Text("Shows an emoji in the menubar that reflects your Mac's current mood. Hover it for a diagnosis.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear { syncLaunchAtLoginStatus() }
    }

    private func applyLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else       { try SMAppService.mainApp.unregister() }
            loginItemStatus = enabled ? L("Registered") : L("Removed")
        } catch {
            loginItemStatus = L("Failed")
            settings.launchAtLogin = !enabled
        }
    }

    private func syncLaunchAtLoginStatus() {
        let registered = SMAppService.mainApp.status == .enabled
        if settings.launchAtLogin != registered { settings.launchAtLogin = registered }
    }
}

// MARK: - About

struct AboutSettingsView: View {
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }
    private var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }
    private let repoURL = URL(string: "https://github.com/tuei2/ResourceMonitor")!

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 56, height: 56)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("ResourceMonitor")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Version \(version) (\(build))")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .textSelection(.enabled)
                    }
                    Spacer()
                }
            }

            Section {
                Button("Check for updates now") {
                    UpdateChecker.shared.checkNow()
                }
                Link("View on GitHub", destination: repoURL)
                Link("Release notes", destination: repoURL.appendingPathComponent("releases"))
            }

            Section {
                Text("A native macOS menu bar system monitor.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } footer: {
                Text("© 2026 tuei2")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Popover

struct PopoverSettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @State private var editingCard: PopoverCard? = nil

    var body: some View {
        VStack(spacing: 0) {
            // Top: layout options
            Form {
                Section("Processes") {
                    Stepper(value: $settings.topProcessesCount, in: 3...10) {
                        HStack {
                            Text("Top processes shown")
                            Spacer()
                            Text("\(settings.topProcessesCount)")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }

                Section("Layout") {
                    Picker("Columns", selection: $settings.popoverColumns) {
                        Text("Single column").tag(1)
                        Text("Two columns").tag(2)
                    }
                    .pickerStyle(.segmented)

                    HStack {
                        Text("Height")
                        Slider(value: $settings.popoverHeight, in: 400...900, step: 20)
                        Text("\(Int(settings.popoverHeight)) pt")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: 52, alignment: .trailing)
                    }

                    Toggle("Enable popout detail windows", isOn: $settings.popoutsEnabled)
                }
            }
            .formStyle(.grouped)
            .fixedSize(horizontal: false, vertical: true)

            Divider()

            if settings.popoverColumns == 2 {
                TwoColumnCardEditor(editingCard: $editingCard)
            } else {
                SingleColumnCardEditor(editingCard: $editingCard)
            }
        }
        .sheet(item: $editingCard) { card in
            CardConfigSheet(card: card)
                .environmentObject(settings)
        }
    }
}

// MARK: - Single-column card editor

private struct SingleColumnCardEditor: View {
    @EnvironmentObject var settings: AppSettings
    @Binding var editingCard: PopoverCard?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Drag to reorder — tap ⚙ to configure each card")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 10)

            List {
                ForEach(settings.popoverCardOrder) { card in
                    CardListRow(card: card, showColumn: false, editingCard: $editingCard)
                }
                .onMove { from, to in settings.popoverCardOrder.move(fromOffsets: from, toOffset: to) }
            }
            .listStyle(.inset)
        }
    }
}

// MARK: - Two-column card editor

private struct TwoColumnCardEditor: View {
    @EnvironmentObject var settings: AppSettings
    @Binding var editingCard: PopoverCard?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Drag to reorder within a column · Click ←→ to move between columns · Tap ⚙ to configure")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 10)

            HStack(alignment: .top, spacing: 8) {
                columnList(title: "Left column", col: 0)
                Divider()
                columnList(title: "Right column", col: 1)
            }
            .padding(.horizontal, 8)
        }
    }

    private func columnList(title: String, col: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 8)

            let cardsInCol = settings.popoverCardOrder.filter { settings.column(for: $0) == col }
            List {
                ForEach(cardsInCol) { card in
                    HStack(spacing: 6) {
                        CardListRow(card: card, showColumn: false, editingCard: $editingCard)
                        Button {
                            settings.setColumn(for: card, col == 0 ? 1 : 0)
                        } label: {
                            Image(systemName: col == 0 ? "arrow.right" : "arrow.left")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help(col == 0 ? "Move to right column" : "Move to left column")
                    }
                }
                .onMove { from, to in
                    // Reorder within the column by rebuilding popoverCardOrder
                    var allCards = settings.popoverCardOrder
                    var colCards = cardsInCol
                    colCards.move(fromOffsets: from, toOffset: to)
                    let colSet = Set(colCards.map(\.rawValue))
                    allCards = allCards.filter { !colSet.contains($0.rawValue) }
                    // Interleave back in their original relative positions
                    var result: [PopoverCard] = []
                    var colIdx = 0
                    for c in allCards {
                        let insertCol = settings.column(for: c)
                        while colIdx < colCards.count && settings.column(for: colCards[colIdx]) == col {
                            result.append(colCards[colIdx]); colIdx += 1
                            if insertCol != col { break }
                        }
                        result.append(c)
                    }
                    while colIdx < colCards.count { result.append(colCards[colIdx]); colIdx += 1 }
                    settings.popoverCardOrder = result
                }
            }
            .listStyle(.inset)
            .frame(maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Shared card list row

private struct CardListRow: View {
    @EnvironmentObject var settings: AppSettings
    let card: PopoverCard
    let showColumn: Bool
    @Binding var editingCard: PopoverCard?

    private var cfg: CardConfig { settings.config(for: card) }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: card.systemImage)
                .frame(width: 18)
                .foregroundStyle(accentColor)
            Text(card.title)
                .foregroundStyle(settings.isEnabled(card) ? .primary : .secondary)
            Spacer()
            // Layout mode chip — only shown for cards that actually implement alternative layouts
            let supportsRing = card == .cpu || card == .ram
            if supportsRing && cfg.layoutMode == .ring {
                Text(cfg.layoutMode.label)
                    .font(.system(size: 9, weight: .medium))
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
                    .foregroundStyle(.secondary)
            }
            // Configure button
            Button { editingCard = card } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            Toggle("", isOn: Binding(
                get: { settings.isEnabled(card) },
                set: { settings.setEnabled(card, $0) }
            ))
            .labelsHidden()
        }
        .padding(.vertical, 2)
    }

    private var accentColor: Color {
        if let hex = cfg.accentHex { return hexColor(hex) }
        return .accentColor
    }
}

// MARK: - Per-card config sheet

private struct CardConfigSheet: View {
    @EnvironmentObject var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    let card: PopoverCard
    @State private var draft: CardConfig

    init(card: PopoverCard) {
        self.card = card
        _draft = State(initialValue: AppSettings.shared.config(for: card))
    }

    private var accentBinding: Binding<Color> {
        Binding(
            get: { draft.accentHex.map { hexColor($0) } ?? .accentColor },
            set: { draft.accentHex = hexString(from: $0) }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            HStack {
                Image(systemName: card.systemImage).foregroundStyle(.tint)
                Text(card.title).font(.headline)
                Spacer()
                Button("Done") {
                    settings.setConfig(for: card, draft)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
            .background(.ultraThinMaterial)

            Divider()

            ScrollView {
                Form {
                    // Ring gauge layout is only implemented in CPUCard and RAMCard
                    if card == .cpu || card == .ram {
                        Section("Layout") {
                            Toggle(isOn: Binding(
                                get: { draft.layoutMode == .ring },
                                set: { draft.layoutMode = $0 ? .ring : .standard }
                            )) {
                                Label("Ring gauge", systemImage: "circle.circle")
                            }
                        }
                    }

                    // Accent color
                    Section("Color") {
                        HStack {
                            Text("Accent color")
                            Spacer()
                            ColorPicker("", selection: accentBinding, supportsOpacity: false)
                                .labelsHidden()
                            Button("Reset") { draft.accentHex = nil }
                                .buttonStyle(.borderless)
                                .foregroundStyle(.secondary)
                        }
                    }

                    // Visible elements
                    let elements = card.availableElements
                    if !elements.isEmpty {
                        Section("Visible elements") {
                            ForEach(elements, id: \.key) { element in
                                Toggle(element.label, isOn: Binding(
                                    get: { draft.shows(element.key) },
                                    set: { visible in
                                        draft.elementVisibility[element.key] = visible
                                    }
                                ))
                            }
                        }
                    }
                }
                .formStyle(.grouped)
                .padding()
            }
        }
        .frame(width: 360, height: 420)
        .background(.regularMaterial)
    }
}

// MARK: - Menubar

struct MenubarSettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Preview — always dark to match actual menubar appearance
            MenubarPreviewBar(appState: appState, settings: settings)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(NSColor.windowBackgroundColor).opacity(0.3))
                .overlay(alignment: .bottom) { Divider() }

            Text("Drag to reorder · toggle elements per metric")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 12)

            List {
                ForEach($settings.menubarItems) { $item in
                    MenubarItemRow(item: $item)
                }
                .onMove { from, to in settings.menubarItems.move(fromOffsets: from, toOffset: to) }
            }
            .listStyle(.inset)
        }
    }
}

// MARK: - Menubar item row

private struct MenubarItemRow: View {
    @Binding var item: MenubarItemConfig

    // Which elements are relevant for this metric
    private var availableElements: [MenubarElement] {
        if item.metric == .ram {
            return MenubarElement.allCases
        }
        return MenubarElement.allCases.filter { $0 != .pressure }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header: drag handle, icon, name, enable toggle
            HStack(spacing: 8) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                Image(systemName: item.metric.systemImage)
                    .frame(width: 18)
                    .foregroundStyle(item.enabled ? Color.accentColor : .secondary)
                Text(item.metric.label)
                    .foregroundStyle(item.enabled ? .primary : .secondary)
                Spacer()
                Toggle("", isOn: $item.enabled)
                    .labelsHidden()
            }

            if item.enabled {
                // Element chips
                HStack(spacing: 6) {
                    ForEach(availableElements) { element in
                        ElementChip(
                            element: element,
                            isOn: item.elements.contains(element),
                            onTap: { toggleElement(element) }
                        )
                    }
                    Spacer()
                    if item.elements.contains(.label) {
                        TextField("Label", text: $item.customLabel)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 72)
                            .font(.system(size: 11))
                    }
                }

                // Appearance-aware color pickers
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .center, spacing: 10) {
                        AppearanceColorPicker(
                            icon: "moon.fill",
                            label: "Donker",
                            hex: $item.darkTintHex
                        )
                        AppearanceColorPicker(
                            icon: "sun.max.fill",
                            label: "Licht",
                            hex: $item.lightTintHex
                        )
                        if item.darkTintHex != nil || item.lightTintHex != nil {
                            Button("System") {
                                item.darkTintHex = nil
                                item.lightTintHex = nil
                            }
                            .font(.system(size: 10))
                            .buttonStyle(.borderless)
                            .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    Text("Thresholds override color")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.vertical, 4)
        .animation(.easeInOut(duration: 0.15), value: item.enabled)
        .animation(.easeInOut(duration: 0.15), value: item.elements)
    }

    private func toggleElement(_ element: MenubarElement) {
        if let idx = item.elements.firstIndex(of: element) {
            item.elements.remove(at: idx)
        } else {
            item.elements.append(element)
            item.elements.sort { a, b in
                let order = MenubarElement.allCases
                return (order.firstIndex(of: a) ?? 0) < (order.firstIndex(of: b) ?? 0)
            }
        }
    }
}

private struct AppearanceColorPicker: View {
    let icon: String
    let label: String
    @Binding var hex: String?

    private var colorBinding: Binding<Color> {
        Binding(
            get: { hex.map { hexColor($0) } ?? .clear },
            set: { newColor in
                let h = hexString(from: newColor)
                hex = (h == "000000") ? nil : h
            }
        )
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize()
            ColorPicker("", selection: colorBinding, supportsOpacity: false)
                .labelsHidden()
                .controlSize(.small)
                .frame(width: 44)
            if hex != nil {
                Button {
                    hex = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .fixedSize()
    }
}

private struct ElementChip: View {
    let element: MenubarElement
    let isOn: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 3) {
                Image(systemName: element.systemImage)
                    .font(.system(size: 9, weight: .medium))
                Text(element.displayName)
                    .font(.system(size: 10, weight: .medium))
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(isOn ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.08),
                        in: Capsule())
            .foregroundStyle(isOn ? Color.accentColor : .secondary)
            .overlay {
                Capsule()
                    .strokeBorder(isOn ? Color.accentColor.opacity(0.4) : Color.clear, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Menubar preview bar

struct MenubarPreviewBar: View {
    let appState: AppState
    let settings: AppSettings

    var body: some View {
        HStack {
            Text("◉  File  Edit  View")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.75))
            Spacer()
            MenubarPreviewLabel(appState: appState, settings: settings)
            Text("9:41")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.75))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color(white: 0.12), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct MenubarPreviewLabel: NSViewRepresentable {
    let appState: AppState
    let settings: AppSettings

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.isEditable = false
        field.isBordered = false
        field.drawsBackground = false
        field.cell?.truncatesLastVisibleLine = false
        // Always render on dark background — force dark appearance so label color = white
        field.appearance = NSAppearance(named: .darkAqua)
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        nsView.attributedStringValue = MenubarRenderer.render(state: appState, settings: settings)
        nsView.sizeToFit()
    }
}

// MARK: - Thresholds

struct ThresholdSettingsView: View {
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        Form {
            Section {
                ThresholdRow(label: "CPU usage",
                             value: $settings.cpuAlertThreshold,
                             unit: "%", range: 50...99, color: .blue)
                ThresholdRow(label: "Memory usage",
                             value: $settings.ramAlertThreshold,
                             unit: "%", range: 50...99, color: .purple)
                ThresholdRow(label: "CPU temperature",
                             value: $settings.tempAlertThreshold,
                             unit: "°C", range: 60...100, color: .orange)

            } header: {
                Text("Warning thresholds")
            } footer: {
                Text("Controls when the warning badge appears in each card. Critical threshold is set at warning + 15%.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Enable alert notifications", isOn: $settings.alertsEnabled)
                    .onChange(of: settings.alertsEnabled) { _, enabled in
                        if enabled { UNPermissionRequest.request() }
                    }
            } header: {
                Text("Notifications")
            } footer: {
                Text("When enabled, a notification fires when a metric stays above its threshold for several consecutive readings.")
                    .foregroundStyle(.secondary)
            }

            Section("Behaviour") {
                LabeledContent("Cooldown between alerts") { Text("5 minutes").foregroundStyle(.secondary) }
                LabeledContent("Debounce readings") { Text("5 consecutive ticks").foregroundStyle(.secondary) }
            }
            .disabled(!settings.alertsEnabled)
        }
        .formStyle(.grouped)
        .padding()
    }
}

private struct ThresholdRow: View {
    let label: String
    @Binding var value: Double
    let unit: String
    let range: ClosedRange<Double>
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            Text(label).frame(width: 140, alignment: .leading)
            Slider(value: $value, in: range, step: 5)
                .accentColor(color)
            Text("\(Int(value))\(unit)")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(color)
                .frame(width: 48, alignment: .trailing)
        }
    }
}

private struct MoodPreviewRow: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("All moods")
                .font(.caption)
                .foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110))], spacing: 6) {
                ForEach(Mood.allCases, id: \.rawValue) { mood in
                    HStack(spacing: 5) {
                        Text(mood.emoji).font(.system(size: 15))
                        Text(mood.rawValue.capitalized)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(.top, 2)
    }
}

private enum UNPermissionRequest {
    static func request() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }
}
