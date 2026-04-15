import Foundation

/// Represents a single open SSH tab in the multi-tab interface.
/// This is an in-memory model only — it is never persisted to GRDB.
struct ActiveSession: Identifiable, Equatable {
    /// Unique ID for this open tab instance. Distinct from `session.id`
    /// so the same Session can theoretically be opened twice (future work).
    let id: UUID
    /// The persisted session this tab was opened from.
    let session: Session
    /// Display label shown in the tab bar. Defaults to `session.name`.
    var label: String

    init(session: Session) {
        self.id = UUID()
        self.session = session
        self.label = session.name
    }
}
