import Testing

/// Marks the suites that hit the simulator's real system Calendars/Reminders
/// store (DW-3.2, DW-3.3). Per the plan's Notes and `docs/code-standards.md`
/// Testing Patterns ("EventKit integration tests hit the simulator's real
/// system store: tag simulator-only, run serially"), these must stay out of
/// the default `make test` run -- see `make test-integration` in the
/// Makefile, which runs only suites carrying this tag via `-only-testing`,
/// while `make test` explicitly skips them via `-skip-testing`.
extension Tag {
    @Tag static var eventKitIntegration: Self
}
