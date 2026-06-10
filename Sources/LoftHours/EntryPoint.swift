import Foundation

/// Process entry point. Normally launches the SwiftUI app; `--selftest` runs a
/// headless check of the Session -> SessionStore -> markdown path so the log
/// writer can be verified without driving the GUI.
@main
enum EntryPoint {
    static func main() {
        if CommandLine.arguments.contains("--selftest") {
            SelfTest.run()
            MainActor.assumeIsolated { SelfTest.runControllerFlow() }
            MainActor.assumeIsolated { SelfTest.runStopwatchTest() }
            SelfTest.runRollupTest()
            SelfTest.runOrphanSweepTest()
            SelfTest.runCalendarTest()
            SelfTest.runWelcomeTest()
            return
        }
        LoftHoursApp.main()
    }
}
