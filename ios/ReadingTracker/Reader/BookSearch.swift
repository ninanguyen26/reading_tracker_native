import Foundation
import ReadiumShared

/// Results of searching the open book, grouped by chapter in reading order.
struct BookSearch {
    enum Status: Equatable { case idle, searching, done, failed(String) }

    struct Section: Identifiable {
        let id: Int
        let title: String
        var results: [Locator]
    }

    var query = ""
    var sections: [Section] = []
    var status: Status = .idle
    /// The result last opened, to mark on the page and offer a way back to the list.
    var selected: Locator?

    var count: Int { sections.reduce(0) { $0 + $1.results.count } }

    /// Adds a page of results, keeping consecutive matches from the same chapter together.
    mutating func append(_ locators: [Locator]) {
        for locator in locators {
            let title = locator.title ?? "Untitled"
            if sections.last?.title == title {
                sections[sections.count - 1].results.append(locator)
            } else {
                sections.append(Section(id: sections.count, title: title, results: [locator]))
            }
        }
    }
}
