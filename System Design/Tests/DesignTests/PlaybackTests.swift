import Foundation
import Testing
@testable import DesignEngine

@Test func olderCheckpointsKeepTheirCurrentRevealAndUseTheNewOpeningAtHandoff() throws {
    let fresh = Exploration(seed: 42, scope: "domestic-solar-power")
    let count = fresh.chapter.order.count
    let oldOpening = max(4, (count + 1) / 2)
    let oldLastBeat = count - oldOpening + 4
    let beatTicks = fresh.chapter.beatTicks
    var plist = try #require(PropertyListSerialization.propertyList(from: fresh.checkpoint(), format: nil) as? [String: Any])
    plist["version"] = 1
    plist["beat"] = oldLastBeat
    plist["tick"] = beatTicks / 8
    plist["age"] = oldLastBeat * (beatTicks + 1) + beatTicks / 8
    let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
    let saved = try #require(Exploration(checkpoint: data))
    var resumed = try #require(Exploration(checkpoint: try saved.checkpoint()))
    #expect(resumed.beat == resumed.chapter.lastBeat && resumed.tick == beatTicks / 8)
    #expect(resumed.chapter.firstCount == oldOpening)
    let incoming = resumed.incomingChapter()
    #expect(incoming.firstCount == 2)
    resumed.advance(beatTicks + 1 - resumed.tick)
    #expect(resumed.beat == 0 && resumed.tick == 0)
    #expect(resumed.chapter.visit == incoming.visit)
    let next = try #require(Exploration(checkpoint: try resumed.checkpoint()))
    #expect(next.chapter.nodeRevealBeats == incoming.nodeRevealBeats)
    #expect(next.chapter.edgeRevealBeats == incoming.edgeRevealBeats)
}

@Test func drawingCadenceDoesNotAffectPlayback() throws {
    var a = Playback(Exploration(seed: 12)), b = a
    a.present(visible: true, animated: true)
    b.present(visible: true, animated: true)
    for _ in 0..<600 { a.advance(elapsed: 0.2) }
    for _ in 0..<2400 { b.advance(elapsed: 0.05) }
    #expect(try a.exploration.checkpoint() == b.exploration.checkpoint())
}

@Test func interruptedRevealsAndHandoffsReachAQuietFrameWithoutStartingAnotherAction() throws {
    let initial = Exploration(seed: 42)
    for beat in [0, 1, initial.chapter.lastBeat] {
        for progress in [0, 0.08, 0.36, 0.57, 0.99] {
            var world = initial
            world.advance(beat * (world.chapter.beatTicks + 1) + Int(Double(world.chapter.beatTicks) * progress))
            var playback = Playback(world)
            playback.present(visible: true, animated: true)
            playback.present(visible: true, animated: false)
            for _ in 0..<48 { playback.advance(elapsed: 0.1) }
            #expect(playback.mode == .still && !playback.needsTimer)
            #expect(playback.exploration.chapter.visit == world.chapter.visit)
            #expect(playback.exploration.beat == beat && playback.exploration.tick == world.restingTick)
            let frame = try playback.exploration.checkpoint()
            playback.advance(elapsed: 3600)
            #expect(try playback.exploration.checkpoint() == frame)
            playback.present(visible: true, animated: true)
            playback.advance(elapsed: 0.2)
            #expect(playback.exploration.age > world.age)
        }
    }
}

@Test func replacementDesktopAndRepeatedShortLocksPreserveTheCursor() throws {
    var playback = Playback(Exploration(seed: 79))
    playback.present(visible: true, animated: false)
    #expect(!playback.needsTimer && playback.exploration.age == 0)
    for _ in 0..<20 {
        playback.present(visible: true, animated: true)
        playback.advance(elapsed: 0.2)
        playback.present(visible: false, animated: true)
        #expect(!playback.needsTimer)
        let saved = playback.exploration
        playback.advance(elapsed: 0.25)
        #expect(playback.exploration.age == saved.age)
        playback = Playback(try #require(Exploration(checkpoint: try saved.checkpoint())))
        playback.present(visible: true, animated: false)
        #expect(playback.mode == .settling && playback.exploration.tick == saved.tick)
        #expect(playback.exploration.elevation == saved.elevation)
        for _ in 0..<40 { playback.advance(elapsed: 0.0625) }
        #expect(playback.exploration.tick == saved.restingTick)
        #expect(playback.exploration.elevation == 0 && !playback.needsTimer)
    }
    #expect(playback.exploration.age >= 60)
}

@Test func settlingBetweenActionsSurvivesSuspensionWithoutStartingTheNextBeat() throws {
    var playback = Playback(Exploration(seed: 42))
    playback.present(visible: true, animated: true)
    let ticks = Int(Double(playback.exploration.chapter.beatTicks) * 0.40)
    for _ in 0..<ticks { playback.advance(elapsed: 1.0 / 16) }
    let locked = playback.exploration
    #expect(locked.tick == locked.restingTick && locked.elevation == 1)
    playback.present(visible: true, animated: false)
    #expect(playback.needsTimer && playback.exploration.elevation == 1)
    for _ in 0..<12 { playback.advance(elapsed: 1.0 / 16) }
    let middle = playback.exploration
    #expect(middle.elevation > 0 && middle.elevation < locked.elevation)
    #expect(middle.age == locked.age)

    playback.present(visible: false, animated: false)
    #expect(!playback.needsTimer)
    var replacement = Playback(try #require(Exploration(checkpoint: try middle.checkpoint())))
    replacement.present(visible: true, animated: false)
    #expect(replacement.exploration.elevation == middle.elevation)
    for _ in 0..<40 {
        replacement.present(visible: true, animated: false)
        replacement.advance(elapsed: 1.0 / 16)
    }
    #expect(!replacement.needsTimer && replacement.exploration.elevation == 0)
    #expect(try replacement.exploration.checkpoint() == locked.restingFrame.checkpoint())
    var idle = Playback(try #require(Exploration(checkpoint: try replacement.exploration.checkpoint())))
    idle.present(visible: true, animated: false)
    #expect(idle.mode == .still && !idle.needsTimer)
}
