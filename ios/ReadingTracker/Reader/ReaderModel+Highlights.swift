import Foundation
import PDFKit
import ReadiumNavigator
import ReadiumShared
import UIKit

/// Highlights: made from the text selection, drawn on the page, edited in a sheet.
/// EPUB highlights are Readium decorations; PDF highlights are PDFKit annotations,
/// since Readium only decorates EPUBs.
extension ReaderModel {
    private static let decorationGroup = "highlights"

    var editingHighlight: Highlight? {
        editing.flatMap { editing in highlights.first { $0.id == editing.id } }
    }

    // MARK: Creating

    /// Saves the current text selection as a highlight. With `openNote`, opens it to add a note.
    func highlightSelection(openNote: Bool) {
        guard let selectable = navigator as? SelectableNavigator,
              let selection = selectable.currentSelection,
              let json = try? selection.locator.jsonString()
        else { return }
        let text = selection.locator.text.highlight?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else { return }

        // For PDFs, remember where on the page the selection is, to draw it later.
        let rects = book.format == .pdf ? currentPDFSelectionRects() : []
        let highlight = Highlight(
            id: UUID().uuidString,
            bookId: book.id,
            locator: json,
            text: text,
            color: .yellow,
            note: "",
            progression: selection.locator.locations.totalProgression ?? locator?.locations.totalProgression ?? 0,
            chapter: selection.locator.title ?? locator?.title,
            pdfRects: Highlight.encode(rects),
            createdAt: Date(),
            updatedAt: Date()
        )
        selectable.clearSelection()
        Task {
            try? await environmentDatabase.addHighlight(highlight)
            if openNote { editing = (highlight.id, true) }
        }
    }

    private func currentPDFSelectionRects() -> [Highlight.PageRect] {
        guard let pdfView, let document = pdfView.document, let selection = pdfView.currentSelection else { return [] }
        return selection.selectionsByLine().flatMap { line in
            line.pages.map { page in
                let bounds = line.bounds(for: page)
                return Highlight.PageRect(
                    page: document.index(for: page),
                    x: bounds.minX, y: bounds.minY, width: bounds.width, height: bounds.height
                )
            }
        }
    }

    // MARK: Editing

    func setColor(_ color: Highlight.Color, of highlight: Highlight) {
        Task { try? await environmentDatabase.updateHighlight(id: highlight.id, color: color) }
    }

    func saveNote(_ note: String, of highlight: Highlight) {
        let note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard note != highlight.note else { return }
        Task { try? await environmentDatabase.updateHighlight(id: highlight.id, note: note) }
    }

    func delete(_ highlight: Highlight) {
        if editing?.id == highlight.id { editing = nil }
        Task { try? await environmentDatabase.deleteHighlight(id: highlight.id) }
    }

    func go(to highlight: Highlight) {
        guard let target = try? Locator(jsonString: highlight.locator) else { return }
        Task { _ = await navigator?.go(to: target, options: .animated) }
    }

    // MARK: Drawing

    func observeHighlights() {
        // Tapping an EPUB highlight opens it.
        (navigator as? DecorableNavigator)?.observeDecorationInteractions(inGroup: Self.decorationGroup) { [weak self] event in
            self?.editing = (event.decoration.id, false)
        }
        let observation = environmentDatabase.observeHighlights(bookId: book.id)
        highlightObservation = Task { [weak self] in
            do {
                for try await highlights in observation {
                    self?.highlights = highlights
                    self?.drawHighlights()
                }
            } catch {}
        }
    }

    /// Redraws every highlight; Readium diffs EPUB decorations itself.
    func drawHighlights() {
        if let decorable = navigator as? DecorableNavigator {
            let decorations = highlights.compactMap { highlight -> Decoration? in
                guard let locator = try? Locator(jsonString: highlight.locator) else { return nil }
                return Decoration(id: highlight.id, locator: locator, style: .highlight(tint: highlight.color.uiColor(in: highlightPalette)))
            }
            decorable.apply(decorations: decorations, in: Self.decorationGroup)
        } else {
            drawPDFHighlights()
        }
    }

    private func drawPDFHighlights() {
        guard let document = pdfView?.document else { return }
        for annotation in pdfAnnotations.values.flatMap({ $0 }) {
            annotation.page?.removeAnnotation(annotation)
        }
        pdfAnnotations = [:]
        for highlight in highlights {
            pdfAnnotations[highlight.id] = highlight.pageRects.compactMap { rect in
                guard let page = document.page(at: rect.page) else { return nil }
                let annotation = PDFAnnotation(bounds: rect.rect, forType: .highlight, withProperties: nil)
                annotation.color = highlight.color.uiColor(in: highlightPalette).withAlphaComponent(0.45)
                page.addAnnotation(annotation)
                return annotation
            }
        }
    }

    /// PDF: opens the highlight under a tap, if there is one. `point` is in the navigator's view.
    func openPDFHighlight(at point: CGPoint) -> Bool {
        guard let pdfView, let document = pdfView.document, let navigatorView = navigator?.view else { return false }
        let inPDFView = pdfView.convert(point, from: navigatorView)
        guard let page = pdfView.page(for: inPDFView, nearest: false) else { return false }
        let pagePoint = pdfView.convert(inPDFView, to: page)
        let pageIndex = document.index(for: page)
        guard let hit = highlights.first(where: { highlight in
            highlight.pageRects.contains { $0.page == pageIndex && $0.rect.insetBy(dx: -2, dy: -2).contains(pagePoint) }
        }) else { return false }
        editing = (hit.id, false)
        return true
    }
}
