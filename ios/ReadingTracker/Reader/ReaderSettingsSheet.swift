import SwiftUI

/// The "Aa" sheet: theme, text and layout.
struct ReaderSettingsSheet: View {
    @Binding var settings: ReaderSettings
    let format: BookFormat
    @Environment(\.dismiss) private var dismiss
    @AppStorage(ReaderSettings.showClockStorageKey) private var showClock = false
    @AppStorage(ReaderSettings.FooterDisplay.storageKey) private var footerDisplay: ReaderSettings.FooterDisplay = .location
    @AppStorage(ReaderSettings.readingSpeedStorageKey) private var readingSpeed = ReaderSettings.defaultReadingSpeed
    @State private var speedEntry: ReadingSpeedEntry.Mode?

    private var isPDF: Bool { format == .pdf }

    var body: some View {
        NavigationStack {
            Form {
                Section("Theme") {
                    HStack(spacing: 10) {
                        ForEach(ReaderSettings.Theme.allCases) { theme in
                            ThemeSwatch(theme: theme, selected: settings.theme == theme) {
                                settings.theme = theme
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .listRowBackground(AppPalette.surface)

                if !isPDF {
                    Section("Text") {
                        HStack {
                            Button {
                                settings.fontSize = max(ReaderSettings.fontSizeRange.lowerBound, settings.fontSize - ReaderSettings.fontSizeStep)
                            } label: {
                                Image(systemName: "textformat.size.smaller").frame(maxWidth: .infinity, minHeight: 32)
                            }
                            .disabled(settings.fontSize <= ReaderSettings.fontSizeRange.lowerBound + 0.001)
                            .accessibilityLabel("Smaller Text")

                            Text(settings.fontSize.formatted(.percent.precision(.fractionLength(0))))
                                .monospacedDigit()
                                .frame(minWidth: 56)
                                .accessibilityIdentifier("font-size")

                            Button {
                                settings.fontSize = min(ReaderSettings.fontSizeRange.upperBound, settings.fontSize + ReaderSettings.fontSizeStep)
                            } label: {
                                Image(systemName: "textformat.size.larger").frame(maxWidth: .infinity, minHeight: 32)
                            }
                            .disabled(settings.fontSize >= ReaderSettings.fontSizeRange.upperBound - 0.001)
                            .accessibilityLabel("Larger Text")
                        }
                        .buttonStyle(.borderless)
                        .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }

                        fontPicker
                        Picker("Line Spacing", selection: $settings.spacing) {
                            ForEach(ReaderSettings.Spacing.allCases) { Text($0.label).tag($0) }
                        }
                        Picker("Text alignment", selection: $settings.textAlignment) {
                            Text("Original").tag(nil as ReaderSettings.Alignment?)
                            ForEach(ReaderSettings.Alignment.allCases) { alignment in
                                Text(alignment.label).tag(Optional(alignment))
                            }
                        }
                        .pickerStyle(.menu)
                        .accessibilityValue(settings.textAlignment?.label ?? "Original")
                        .accessibilityIdentifier("reader-text-alignment")
                        Picker("Margins", selection: $settings.margins) {
                            ForEach(ReaderSettings.Margins.allCases) { Text($0.label).tag($0) }
                        }
                    }
                    .listRowBackground(AppPalette.surface)
                }

                Section {
                    Picker("Layout", selection: $settings.scroll) {
                        Text("Pages").tag(false)
                        Text("Scroll").tag(true)
                    }
                    .pickerStyle(.segmented)

                    Toggle("Show clock while reading", isOn: $showClock)
                        .accessibilityIdentifier("reader-show-clock")

                    if !isPDF {
                        Picker("Footer display", selection: $footerDisplay) {
                            ForEach(ReaderSettings.FooterDisplay.allCases, id: \.self) { display in
                                Text(display.label).tag(display)
                            }
                        }
                        .pickerStyle(.menu)
                        .accessibilityLabel("Footer display")
                        .accessibilityValue(footerDisplay.label)
                        .accessibilityIdentifier("footer-display")
                    }
                } header: {
                    Text("Layout")
                } footer: {
                    if isPDF {
                        Text("PDFs keep their original layout, so text size and fonts can’t be changed. Pinch to zoom.")
                    }
                }
                .listRowBackground(AppPalette.surface)

                if !isPDF {
                    Section {
                        readingSpeedPicker
                        Button("Stopwatch calculator") { speedEntry = .stopwatch }
                    } footer: {
                        Text("This speed is used for chapter and book estimates.")
                    }
                    .listRowBackground(AppPalette.surface)
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppPalette.background)
            .foregroundStyle(AppPalette.text)
            .toolbarBackground(AppPalette.surface, for: .navigationBar)
            .navigationTitle("Reading Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .sheet(item: $speedEntry) { mode in
            ReadingSpeedEntry(mode: mode, currentSpeed: readingSpeed) { readingSpeed = $0 }
        }
    }

    private var readingSpeedPicker: some View {
        Button {
            speedEntry = .speed
        } label: {
            HStack {
                Text("Reading speed")
                    .foregroundStyle(AppPalette.text)
                Spacer()
                Text("\(readingSpeed) WPM")
                    .monospacedDigit()
                    .foregroundStyle(AppPalette.secondaryText)
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(AppPalette.secondaryText)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("Reading speed")
        .accessibilityValue("\(readingSpeed) WPM")
        .accessibilityIdentifier("reading-speed")
    }

    private var fontPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Font")
                .accessibilityAddTraits(.isHeader)

            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(ReaderSettings.Font.allCases) { font in
                            FontSample(font: font, selected: settings.font == font) {
                                settings.font = font
                            }
                            .id(font)
                        }
                    }
                    .padding(.bottom, 6)
                }
                .accessibilityIdentifier("reader-font-options")
                .onAppear { proxy.scrollTo(settings.font, anchor: .center) }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct ReadingSpeedEntry: View {
    enum Mode: String, Identifiable {
        case speed, stopwatch
        var id: Self { self }
    }

    private static let passage = """
        On Saturday morning, Mara took the long way to the market. Rain had fallen before dawn, and small pools of water still shone between the stones. The bakery door was open. Warm air carried the smell of bread across the street. She bought a loaf and put it in her bag beside a jar she planned to return.

        At the end of the lane, a man was setting out boxes of pears. One box tilted, and a pear rolled under his table. Mara caught it with the toe of her shoe. The man laughed and offered her the pear. She wiped it on her sleeve and took a bite as she walked toward the river.

        Two children were folding paper boats on the steps. The younger child kept pressing the folds flat with both hands. When the boats were ready, the children set them on the water and watched them drift toward the bridge. One boat tipped over in the shade. The other spun once, caught the current, and floated past the farthest stone. Mara stayed until it slipped out of sight. Then she tucked the bread under her arm and turned home, following the quiet path along the riverbank.
        """
    private static let passageWords = BookPageCounter.wordCount(passage)

    let mode: Mode
    let onSave: (Int) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var entry: String
    @State private var stopwatchStart: ContinuousClock.Instant?
    @FocusState private var entryFocused: Bool

    init(mode: Mode, currentSpeed: Int, onSave: @escaping (Int) -> Void) {
        self.mode = mode
        self.onSave = onSave
        _entry = State(initialValue: mode == .speed ? String(currentSpeed) : "")
    }

    private var estimatedSpeed: Int? {
        guard let value = Int(entry.trimmingCharacters(in: .whitespacesAndNewlines)), value > 0 else { return nil }
        return mode == .speed ? value : Int((Double(Self.passageWords * 60) / Double(value)).rounded())
    }

    private var speed: Int? {
        guard let estimatedSpeed, ReaderSettings.readingSpeedRange.contains(estimatedSpeed) else { return nil }
        return estimatedSpeed
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                Form {
                    if mode == .stopwatch {
                        Section {
                            Text("Start the stopwatch, read the full passage at your normal pace, then tap Stop. You can also enter the time in seconds.")
                                .font(.subheadline)
                                .foregroundStyle(AppPalette.secondaryText)
                            Text(Self.passage)
                                .lineSpacing(4)
                        } header: {
                            Text("\(Self.passageWords)-word sample")
                        }
                        .listRowBackground(AppPalette.surface)
                        .id("stopwatch-passage")
                    }

                    Section {
                        if mode == .speed {
                            HStack {
                                ForEach([150, ReaderSettings.defaultReadingSpeed, 250], id: \.self) { preset in
                                    Button("\(preset) WPM") { entry = String(preset) }
                                        .buttonStyle(.bordered)
                                        .tint(speed == preset ? AppPalette.accent : AppPalette.secondaryText)
                                        .accessibilityAddTraits(speed == preset ? .isSelected : [])
                                }
                            }
                        }
                        TextField(mode == .speed ? "Words per minute" : "Total seconds", text: $entry)
                            .keyboardType(.numberPad)
                            .focused($entryFocused)
                            .disabled(stopwatchStart != nil)
                            .accessibilityIdentifier("reading-speed-entry")
                    } header: {
                        Text(mode == .speed ? "Reading speed" : "Elapsed time")
                    } footer: {
                        if mode == .speed, !entry.isEmpty, speed == nil {
                            Text("Enter a whole number from 10 to 1,000.")
                        }
                    }
                    .listRowBackground(AppPalette.surface)

                    if mode == .stopwatch {
                        Section {
                            stopwatchResult
                                .id("stopwatch-result")
                            if !entry.isEmpty {
                                Button("Time another sample") {
                                    entryFocused = false
                                    entry = ""
                                    withAnimation { proxy.scrollTo("stopwatch-passage", anchor: .top) }
                                }
                            }
                        }
                        .listRowBackground(AppPalette.surface)
                    }
                }
                .scrollContentBackground(.hidden)
                .background(AppPalette.background)
                .foregroundStyle(AppPalette.text)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if mode == .stopwatch && entry.isEmpty && !entryFocused {
                        stopwatchControls
                    }
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: stopwatchStart) { start in
                    if start == nil {
                        withAnimation { proxy.scrollTo("stopwatch-result", anchor: .bottom) }
                    }
                }
                .onChange(of: speed != nil) { hasValidSpeed in
                    if mode == .stopwatch && entryFocused && hasValidSpeed {
                        withAnimation { proxy.scrollTo("stopwatch-result", anchor: .bottom) }
                    }
                }
            }
            .navigationTitle(mode == .speed ? "Reading speed" : "Stopwatch calculator")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if mode == .speed {
                        Button("Save speed", action: saveSpeed)
                            .disabled(speed == nil)
                    }
                }
            }
        }
    }

    private var stopwatchResult: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Estimated reading speed")
                .font(.subheadline.weight(.semibold))
            if let estimatedSpeed {
                Text("\(estimatedSpeed) WPM")
                    .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(AppPalette.accent)
                    .accessibilityIdentifier("calculated-reading-speed")
            }
            Text(resultDescription)
                .font(.subheadline)
                .foregroundStyle(AppPalette.secondaryText)
                .accessibilityIdentifier("reading-speed-explanation")

            Button(action: saveSpeed) {
                Text("Save speed")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(AppPrimaryButtonStyle())
            .disabled(speed == nil || stopwatchStart != nil)
            .padding(.top, 4)
        }
        .padding(.vertical, 8)
    }

    private var resultDescription: String {
        if speed != nil {
            return "WPM means words per minute. Save this pace to update the time left in your chapter and book."
        }
        if !entry.isEmpty {
            return estimatedSpeed == nil
                ? "Enter the elapsed time as a positive whole number of seconds."
                : "The reader supports 10 to 1,000 words per minute. Check the elapsed time or time the full passage again."
        }
        return "Stop the stopwatch or enter the elapsed seconds to see your pace."
    }

    private func saveSpeed() {
        guard stopwatchStart == nil, let speed else { return }
        onSave(speed)
        dismiss()
    }

    private var stopwatchControls: some View {
        HStack(spacing: 12) {
            Image(systemName: "stopwatch")
                .foregroundStyle(AppPalette.accent)
                .accessibilityHidden(true)
            if let start = stopwatchStart {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Text(start.duration(to: .now).formatted(.time(pattern: .minuteSecond)))
                        .monospacedDigit()
                }
            } else {
                Text("0:00")
                    .monospacedDigit()
            }
            Spacer()
            Button(stopwatchStart == nil ? "Start" : "Stop") {
                if let start = stopwatchStart {
                    let seconds = start.duration(to: .now) / .seconds(1)
                    entry = String(max(1, Int(seconds.rounded())))
                    stopwatchStart = nil
                } else {
                    entry = ""
                    stopwatchStart = .now
                }
            }
            .buttonStyle(AppPrimaryButtonStyle())
            .accessibilityLabel(stopwatchStart == nil ? "Start stopwatch" : "Stop stopwatch")
        }
        .font(.headline)
        .padding(.leading, 16)
        .padding(6)
        .background(AppPalette.surface, in: Capsule())
        .overlay { Capsule().strokeBorder(AppPalette.border) }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }
}

private struct FontSample: View {
    let font: ReaderSettings.Font
    let selected: Bool
    let action: () -> Void

    private var sampleFont: Font {
        switch font {
        case .original: .subheadline
        case .serif: .custom("IowanOldStyle-Roman", size: 20, relativeTo: .title3)
        case .sans: .title3
        case .newYork: .system(.title3, design: .serif)
        case .georgia: .custom("Georgia", size: 20, relativeTo: .title3)
        case .palatino: .custom("Palatino-Roman", size: 20, relativeTo: .title3)
        case .verdana: .custom("Verdana", size: 20, relativeTo: .title3)
        case .charter: .custom("Charter-Roman", size: 20, relativeTo: .title3)
        case .baskerville: .custom("Baskerville", size: 20, relativeTo: .title3)
        }
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(font.label)
                    Image(systemName: "checkmark")
                        .opacity(selected ? 1 : 0)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppPalette.secondaryText)

                Text(font == .original ? "Book’s own font" : "The next page")
                    .font(sampleFont)
                    .foregroundStyle(AppPalette.text)
            }
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(minWidth: 136, alignment: .leading)
            .background(AppPalette.secondarySurface, in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(selected ? AppPalette.accent : AppPalette.border, lineWidth: selected ? 2 : 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(font.label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct ThemeSwatch: View {
    let theme: ReaderSettings.Theme
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    if theme == .system {
                        // Half light, half dark.
                        HStack(spacing: 0) {
                            Color.white
                            Color.black
                        }
                    } else {
                        ReaderSettings(theme: theme).palette(systemDark: false).background
                    }
                    Text("Aa")
                        .font(.system(.body, design: .serif))
                        // Mid-grey reads on both halves of the "Auto" swatch.
                        .foregroundStyle(theme == .system ? Color.gray : theme == .dark ? .white : .black)
                }
                .frame(height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(selected ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: selected ? 2.5 : 1)
                )
                Text(theme.label)
                    .font(.caption)
                    .foregroundStyle(selected ? .primary : .secondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(theme.label) theme")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}
