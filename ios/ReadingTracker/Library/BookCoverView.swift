import SwiftUI

/// A book's cover image, or a generated cover with its title when it has none.
struct BookCoverView: View {
    let book: Book
    let coverURL: URL?

    // Muted colors, picked from the title so each book keeps its color.
    private static let palette: [Color] = [
        Color(red: 0.29, green: 0.36, blue: 0.40), Color(red: 0.48, green: 0.36, blue: 0.35),
        Color(red: 0.36, green: 0.43, blue: 0.31), Color(red: 0.42, green: 0.35, blue: 0.48),
        Color(red: 0.54, green: 0.43, blue: 0.23), Color(red: 0.25, green: 0.37, blue: 0.50),
    ]

    private var placeholderColor: Color {
        let hash = book.title.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0x7fffffff }
        return Self.palette[hash % Self.palette.count]
    }

    var body: some View {
        // A fixed 2:3 frame; the image fills it as an overlay, so a large
        // cover image can never make the frame (and the grid) wider.
        Color.clear
            .aspectRatio(2.0 / 3.0, contentMode: .fit)
            .overlay {
                if let coverURL, let image = UIImage(contentsOfFile: coverURL.path) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    VStack(alignment: .leading) {
                        Text(book.title)
                            .font(.system(.headline, design: .serif))
                            .lineLimit(5)
                        Spacer()
                        Text(book.author)
                            .font(.caption)
                            .opacity(0.8)
                            .lineLimit(2)
                    }
                    .foregroundStyle(.white)
                    .padding(10)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .background(placeholderColor)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(.black.opacity(0.08)))
            .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
            .accessibilityHidden(true)
    }
}
