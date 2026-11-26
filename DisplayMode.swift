import Foundation

enum DisplayMode: String, Codable, CaseIterable {
    case touchBar
    case notch
    case both
    case hidden

    /// Keep existing users on the original Touch Bar output until they choose notch output.
    static let defaultMode: DisplayMode = .touchBar

    var showsTouchBar: Bool {
        self == .touchBar || self == .both
    }

    var showsNotch: Bool {
        self == .notch || self == .both
    }

    var displayName: String {
        switch self {
        case .touchBar: return L10n.tr("display.touchBar")
        case .notch: return L10n.tr("display.notch")
        case .both: return L10n.tr("display.both")
        case .hidden: return L10n.tr("display.hidden")
        }
    }
}
