import SwiftUI

/// The "Aa" sheet: theme, text and layout.
struct ReaderSettingsSheet: View {
    @Binding var settings: ReaderSettings
    let format: BookFormat
    @Environment(\.dismiss) private var dismiss
    @AppStorage(ReaderSettings.FooterDisplay.storageKey) private var footerDisplay: ReaderSettings.FooterDisplay = .location
    @AppStorage(ReaderSettings.readingSpeedStorageKey) private var readingSpeed = ReaderSettings.defaultReadingSpeed

    private var isPDF: Bool { format == .pdf }
    private let readingSpeedStep = 10

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
                        readingSpeedControl
                    } footer: {
                        Text("This speed is used for chapter and book estimates. To find yours, read at your usual pace for one minute using a stopwatch, then count the words you read.")
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
    }

    private var readingSpeedControl: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Reading speed")
                Text("\(readingSpeed) words per minute")
                    .font(.subheadline)
                    .foregroundStyle(AppPalette.secondaryText)
                    .accessibilityIdentifier("reading-speed-value")
            }
            Spacer(minLength: 8)
            Button {
                readingSpeed = max(ReaderSettings.readingSpeedRange.lowerBound, readingSpeed - readingSpeedStep)
            } label: {
                Image(systemName: "minus").frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .disabled(readingSpeed <= ReaderSettings.readingSpeedRange.lowerBound)
            .accessibilityLabel("Decrease reading speed")

            Button {
                readingSpeed = min(ReaderSettings.readingSpeedRange.upperBound, readingSpeed + readingSpeedStep)
            } label: {
                Image(systemName: "plus").frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .disabled(readingSpeed >= ReaderSettings.readingSpeedRange.upperBound)
            .accessibilityLabel("Increase reading speed")
        }
        .buttonStyle(.borderless)
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
