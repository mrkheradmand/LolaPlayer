import Foundation
import CoreGraphics
import Testing
@testable import PlayerCore

struct WindowPlacementTests {
    let screen = CGRect(x: 0, y: 0, width: 1800, height: 1000)
    @Test func libraryPrefersRightThenFreeSpaceOnLeft() {
        let player = CGRect(x: 20, y: 200, width: 1000, height: 700)
        let right = WindowPlacement.library(beside: player, screens: [screen], size: CGSize(width: 440, height: 620), fullScreen: false)
        #expect(right.minX == player.maxX + 12 && !right.intersects(player))
        let moved = player.offsetBy(dx: 750, dy: 0)
        let left = WindowPlacement.library(beside: moved, screens: [screen], size: right.size, fullScreen: false)
        #expect(left.maxX == moved.minX - 12 && !left.intersects(moved))
    }
    @Test func otherMonitorProvidesFreeSpace() {
        let second = screen.offsetBy(dx: 1800, dy: 0)
        let frame = WindowPlacement.library(beside: screen, screens: [screen, second], size: CGSize(width: 440, height: 620), fullScreen: false)
        #expect(second.contains(frame) && !frame.intersects(screen))
    }
    @Test func fullScreenFloatsAtRightCenter() {
        let frame = WindowPlacement.library(beside: screen, screens: [screen], size: CGSize(width: 440, height: 620), fullScreen: true)
        #expect(frame.maxX == screen.maxX - 24 && frame.midY == screen.midY)
    }
    @Test func restoringHandlesDisconnectedOrSmallerScreens() throws {
        let saved = CGRect(x: -2200, y: 1400, width: 2400, height: 1200)
        let frame = try #require(WindowPlacement.restored(saved, screens: [screen], minimum: CGSize(width: 800, height: 420)))
        #expect(screen.contains(frame))
        #expect(WindowPlacement.restored(CGRect(x: 0, y: 0, width: CGFloat.nan, height: 100), screens: [screen], minimum: .zero) == nil)
    }
    @Test func restoringPreservesExactPositionAndSizeOnExistingMonitor() {
        let saved = CGRect(x: 1900, y: 150, width: 1000, height: 700)
        #expect(WindowPlacement.restored(saved, screens: [screen, screen.offsetBy(dx: 1800, dy: 0)], minimum: .zero) == saved)
    }
}
