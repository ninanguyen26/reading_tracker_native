import SwiftUI

/// The "Aa" sheet: theme, text and layout.
struct ReaderSettingsSheet: View {
    @Binding var settings: ReaderSettings
    let format: BookFormat
    @Environment(\.dismiss) private var dismiss

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

                        Picker("Font", selection: $settings.font) {
                            ForEach(ReaderSettings.Font.allCases) { Text($0.label).tag($0) }
                        }
                        Picker("Line Spacing", selection: $settings.spacing) {
                            ForEach(ReaderSettings.Spacing.allCases) { Text($0.label).tag($0) }
                        }
                        Picker("Margins", selection: $settings.margins) {
                            ForEach(ReaderSettings.Margins.allCases) { Text($0.label).tag($0) }
                        }
                    }
                }

                Section {
                    Picker("Layout", selection: $settings.scroll) {
                        Text("Pages").tag(false)
                        Text("Scroll").tag(true)
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Layout")
                } footer: {
                    if isPDF {
                        Text("PDFs keep their original layout, so text size and fonts can’t be changed. Pinch to zoom.")
                    }
                }
            }
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
