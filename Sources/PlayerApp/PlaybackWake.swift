import Foundation
import IOKit.pwr_mgt

/// Own the display-sleep assertion only while media is playing.
@MainActor final class PlaybackWake {
    private var assertion = IOPMAssertionID(0)
    private var userActivity = IOPMAssertionID(0)
    private var lastActivity = -Double.infinity

    func update(active: Bool) {
        if active {
            if assertion == 0 {
                IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                                           IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                           "Lola Player playback" as CFString, &assertion)
            }
            let now = ProcessInfo.processInfo.systemUptime
            if now - lastActivity >= 30 {
                IOPMAssertionDeclareUserActivity("Lola Player playback" as CFString,
                                                kIOPMUserActiveLocal, &userActivity)
                lastActivity = now
            }
        } else {
            if assertion != 0 { IOPMAssertionRelease(assertion); assertion = 0 }
            if userActivity != 0 { IOPMAssertionRelease(userActivity); userActivity = 0 }
            lastActivity = -.infinity
        }
    }
}
