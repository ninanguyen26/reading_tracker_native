import ReadiumNavigator
import SwiftUI
import UIKit

/// Hosts a Readium navigator and wires up page-turning input.
final class ReaderHostViewController: UIViewController, UIGestureRecognizerDelegate {
    enum TapZone { case left, middle, right }

    let navigator: VisualNavigator & UIViewController
    /// In scroll mode taps don't turn pages; they only show or hide the toolbars.
    private let isScrolling: () -> Bool
    private let onTapCenter: () -> Void
    private let onPageTurn: () -> Void
    /// Must be kept alive, or the navigator stops responding to edge taps.
    private var directionalAdapter: DirectionalNavigationAdapter?

    init(
        navigator: VisualNavigator & UIViewController,
        isScrolling: @escaping () -> Bool,
        onTapCenter: @escaping () -> Void,
        onPageTurn: @escaping () -> Void
    ) {
        self.navigator = navigator
        self.isScrolling = isScrolling
        self.onTapCenter = onTapCenter
        self.onPageTurn = onPageTurn
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        addChild(navigator)
        navigator.view.frame = view.bounds
        navigator.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(navigator.view)
        navigator.didMove(toParent: self)

        if navigator is PDFNavigatorViewController {
            installPDFTapRecognizer()
        } else {
            installNavigatorInput()
        }
    }

    /// EPUB: Readium's input events. Edge taps and arrow/space keys turn
    /// pages; any other tap shows or hides the toolbars.
    private func installNavigatorInput() {
        let adapter = DirectionalNavigationAdapter(
            pointerPolicy: .init(types: [.mouse, .touch]),
            animatedTransition: true,
            onNavigation: { [weak self] in self?.onPageTurn() }
        )
        adapter.bind(to: navigator)
        directionalAdapter = adapter

        navigator.addObserver(.activate { [weak self] _ in
            self?.onTapCenter()
            return true
        })
    }

    /// PDF: Readium's tap recognizer waits for PDFKit's own single-tap
    /// recognizers to fail, which on recent iOS versions never happens, so
    /// taps are recognized here instead, alongside PDFKit's.
    private func installPDFTapRecognizer() {
        let tap = UITapGestureRecognizer(target: self, action: #selector(handlePDFTap(_:)))
        tap.delegate = self
        tap.cancelsTouchesInView = false
        // Let double-tap-to-zoom win over a single tap.
        for case let doubleTap as UITapGestureRecognizer in allGestureRecognizers(in: navigator.view)
        where doubleTap.numberOfTapsRequired == 2 {
            tap.require(toFail: doubleTap)
        }
        navigator.view.addGestureRecognizer(tap)

        // Keyboard: arrows and space still go through Readium.
        let adapter = DirectionalNavigationAdapter(
            pointerPolicy: .init(types: []),
            animatedTransition: true,
            onNavigation: { [weak self] in self?.onPageTurn() }
        )
        adapter.bind(to: navigator)
        directionalAdapter = adapter
    }

    @objc private func handlePDFTap(_ gesture: UITapGestureRecognizer) {
        let point = gesture.location(in: navigator.view)
        if isScrolling() { return onTapCenter() }
        switch Self.zone(for: point.x, width: navigator.view.bounds.width) {
        case .left:
            Task { if await navigator.goLeft(options: .animated) { onPageTurn() } }
        case .right:
            Task { if await navigator.goRight(options: .animated) { onPageTurn() } }
        case .middle:
            onTapCenter()
        }
    }

    /// Left and right 30% (at least 80pt) turn pages, matching Readium's EPUB edges.
    static func zone(for x: CGFloat, width: CGFloat) -> TapZone {
        let edge = max(80, width * 0.3)
        if x <= edge { return .left }
        if x >= width - edge { return .right }
        return .middle
    }

    private func allGestureRecognizers(in view: UIView) -> [UIGestureRecognizer] {
        (view.gestureRecognizers ?? []) + view.subviews.flatMap(allGestureRecognizers(in:))
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }
}

/// Puts the host view controller into SwiftUI.
struct ReaderContainer: UIViewControllerRepresentable {
    let viewController: ReaderHostViewController

    func makeUIViewController(context: Context) -> ReaderHostViewController { viewController }
    func updateUIViewController(_ uiViewController: ReaderHostViewController, context: Context) {}
}
