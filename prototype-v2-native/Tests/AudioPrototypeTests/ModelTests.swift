import XCTest
import AVFoundation
@testable import AudioPrototype
final class ModelTests: XCTestCase {

    func testVirtualEarIsolationInForwardAcousticModel() {
        // Evaluate the FIR and then propagate BOTH speaker outputs to BOTH ears.
        // A left-only input should arrive primarily at the left ear, even turned around.
        for heading in [0.0, 30, 180, 210] {
            var room = Room(); room.heading = heading; room.virtualHeadphones = true
            let filters = EarFilters(room: room), paths = room.calculations(2)
            for frequency in [1000.0, 2000.0] {
                let w = 2 * Double.pi * frequency / 48000
                var ears = [(0.0,0.0),(0.0,0.0)]
                for speaker in 0..<2 {
                    var real = 0.0, imaginary = 0.0
                    for (n,tap) in filters.taps[speaker*2].enumerated() {
                        real += tap*cos(w*Double(n)); imaginary -= tap*sin(w*Double(n))
                    }
                    for ear in 0..<2 {
                        let d = ear == 0 ? paths[speaker].leftEar : paths[speaker].rightEar
                        let phase = -w*48000*(filters.delay[speaker]+d/343)
                        let gain = filters.gain[speaker]*2/d
                        ears[ear].0 += gain*(real*cos(phase)-imaginary*sin(phase))
                        ears[ear].1 += gain*(real*sin(phase)+imaginary*cos(phase))
                    }
                }
                let desired = hypot(ears[0].0,ears[0].1), leakage = hypot(ears[1].0,ears[1].1)
                XCTAssertGreaterThan(desired,0.5)
                // Oblique geometry has frequency-dependent weak spots; require at least
                // 3.7 dB separation there and 9 dB facing forward/back.
                XCTAssertLessThan(leakage/desired,heading == 0 || heading == 180 ? 0.35 : 0.65,"heading \(heading), frequency \(frequency)")
            }
        }
    }
    func testVirtualSidewaysFiltersRemainBounded() {
        var room = Room(); room.heading = 90; room.virtualHeadphones = true
        let f = EarFilters(room:room)
        XCTAssertTrue(f.taps.flatMap { $0 }.allSatisfy { $0.isFinite })
        for taps in f.taps { XCTAssertLessThan(taps.reduce(0) { $0+abs($1) },8) }
    }
    func testVirtualRendererAndReset() {
        var room = Room(); room.virtualHeadphones = true
        let r = Renderer()
        r.data = AudioData(left:(0..<12000).map { Float(0.1*sin(Double($0)*2 * .pi*1000/48000)) },right:Array(repeating:0,count:12000))
        r.target = DSPSettings(room:room); r.current = r.target
        r.playing = true; r.envelope = 1
        let b = render(r,frames:8192)
        for i in 0..<2 {
            let values = Array(UnsafeBufferPointer(start:b.floatChannelData![i],count:8192))
            XCTAssertTrue(values.allSatisfy { $0.isFinite })
            XCTAssertGreaterThan(values.map { abs($0) }.max()!,0.001)
        }
        let filters = r.target.earFilters!
        for i in 0..<2 {
            for frame in stride(from:7000,to:8192,by:37) {
                var expected = 0.0
                for (n,tap) in filters.taps[i*2].enumerated() {
                    expected += tap*0.1*sin((Double(frame-n)-r.target.delay[i]*48000)*2 * .pi*1000/48000)
                }
                expected *= r.target.gain[i]*r.target.master
                XCTAssertEqual(Double(b.floatChannelData![i][frame]),expected,accuracy:0.00015)
            }
        }
        r.resetFilters()
        XCTAssertTrue(r.outputHistory.flatMap { $0 }.allSatisfy { $0 == 0 })
    }

    func testRotationIndependentOfCancellation() {
        var room = Room()
        XCTAssertFalse(room.separation)
        let front = DSPSettings(room: room)
        room.heading = 180
        let back = DSPSettings(room: room)
        XCTAssertEqual(front.left[0], back.right[0], accuracy: 1e-9)
        XCTAssertGreaterThan(abs(front.left[0] - back.left[0]), 0.3)
        XCTAssertEqual(back.cancel, [0,0])
        room.rotation = false
        XCTAssertEqual(DSPSettings(room: room).left, [1,0])
        XCTAssertEqual(DSPSettings(room: room).right, [0,1])
    }
    func testCentreLineVersusSidewaysDelay() {
        var room = Room()
        for y in [1.0, 2.0, 4.0] {
            room.y = y
            XCTAssertEqual(DSPSettings(room: room).delay[0], 0, accuracy: 1e-9)
            XCTAssertEqual(DSPSettings(room: room).delay[1], 0, accuracy: 1e-9)
        }
        room.x = 1; room.y = 3
        let left = DSPSettings(room: room)
        XCTAssertGreaterThan(left.delay[0], 0.002)
        XCTAssertEqual(left.delay[1], 0, accuracy: 1e-9)
        room.x = 3
        let right = DSPSettings(room: room)
        XCTAssertEqual(right.delay[0], 0, accuracy: 1e-9)
        XCTAssertEqual(right.delay[1], left.delay[0], accuracy: 1e-9)
    }
    func testRotationChangesRenderedStereo() {
        var room = Room(); room.volume = false; room.alignment = false
        let r = Renderer()
        r.data = AudioData(left: Array(repeating: 0.2, count: 48000), right: Array(repeating: 0, count: 48000))
        r.target = DSPSettings(room: room); r.target.master = 1; r.current = r.target
        r.envelope = 1; r.playing = true
        let a = render(r, frames: 512)
        let leftBefore = a.floatChannelData![0][500], rightBefore = a.floatChannelData![1][500]
        room.heading = 180; r.target = DSPSettings(room: room); r.target.master = 1
        let b = render(r, frames: 8192)
        XCTAssertEqual(b.floatChannelData![0][8191], rightBefore, accuracy: 1e-5)
        XCTAssertEqual(b.floatChannelData![1][8191], leftBefore, accuracy: 1e-5)
    }
    func testHeightAndEars() {
        var r = Room(); r.x = 0; r.y = 0; r.height = 0; r.speakers[0].x = 3; r.speakers[0].y = 4; r.speakers[0].z = 12
        XCTAssertEqual(r.calculations()[0].distance,13,accuracy:1e-9)
        r.heading = 90
        XCTAssertEqual(r.ears[0].0,0,accuracy:1e-9)
        XCTAssertEqual(r.ears[0].1,-0.09,accuracy:1e-9)
    }
    func testArrivalAndAdditiveTrims() {
        var r = Room(); r.x = 0.8
        let c = r.calculations()
        XCTAssertEqual(c[0].distance/343+c[0].automaticMS/1000,c[1].distance/343+c[1].automaticMS/1000,accuracy:1e-9)
        r.speakers[0].trim = 3; r.speakers[0].delayTrim = 7
        let d = r.calculations()[0]
        XCTAssertEqual(d.finalDB,c[0].automaticDB+3,accuracy:1e-9)
        XCTAssertEqual(d.finalMS,c[0].automaticMS+7,accuracy:1e-9)
        r.volume = false; r.alignment = false
        XCTAssertEqual(r.calculations()[0].finalDB,3)
        XCTAssertEqual(r.calculations()[0].finalMS,7)
    }
    func testInverseDistanceCompensation() {
        var r = Room()
        for y in [1.0,2.0,4.0] {
            r.y = y
            for c in r.calculations() { XCTAssertEqual(pow(10,c.finalDB/20)/c.distance,0.5,accuracy:1e-9) }
        }
    }
    func testFourSpeakerPlanningDoesNotChangeStereo() {
        var r = Room(); let a = DSPSettings(room:r)
        r.count = 4; r.speakers[3].y = 20
        let b = DSPSettings(room:r)
        XCTAssertEqual(a.delay,b.delay); XCTAssertEqual(a.gain,b.gain); XCTAssertEqual(r.calculations().count,4)
    }
    func testHeadRotationAndMute() {
        var r = Room(); r.separation = true
        let front = DSPSettings(room:r); r.heading = 180; let back = DSPSettings(room:r)
        XCTAssertEqual(front.left[0],back.right[0],accuracy:1e-9)
        r.speakers[0].solo = true
        XCTAssertEqual(DSPSettings(room:r).gain[1],0)
        r.speakers[0].mute = true
        XCTAssertEqual(DSPSettings(room:r).gain[0],0)
    }
    func testConstraints() {
        var r = Room(); r.width = .nan; r.x = 100; r.speakers[0].z = -1; r.constrain()
        XCTAssertEqual(r.width,1); XCTAssertEqual(r.x,1); XCTAssertEqual(r.speakers[0].z,0)
    }
    func render(_ r: Renderer, frames: Int) -> AVAudioPCMBuffer {
        let b = AVAudioPCMBuffer(pcmFormat: AVAudioFormat(standardFormatWithSampleRate:48000,channels:2)!,frameCapacity:AVAudioFrameCount(frames))!
        b.frameLength = AVAudioFrameCount(frames)
        XCTAssertEqual(r.render(frames,b.mutableAudioBufferList),0)
        return b
    }
    func testOriginalStereoAndPause() {
        let r = Renderer(); r.data = AudioData(left:Array(repeating:0.2,count:48000),right:Array(repeating:-0.3,count:48000))
        r.target.processed = false; r.target.master = 1; r.current.master = 1; r.wet = 0; r.envelope = 1; r.playing = true
        let b = render(r,frames:512)
        XCTAssertEqual(b.floatChannelData![0][400],0.2,accuracy:1e-6); XCTAssertEqual(b.floatChannelData![1][400],-0.3,accuracy:1e-6)
        let pos = r.position; r.playing = false
        let silent = render(r,frames:512)
        XCTAssertEqual(r.position,pos); XCTAssertEqual(silent.floatChannelData![0][0],0)
    }
    func testDelayImpulseAndMute() {
        let r = Renderer(); var left = Array(repeating:Float(0),count:4800); left[0] = 0.5
        r.data = AudioData(left:left,right:left); r.target.left = [1,0]; r.target.right = [0,1]; r.target.delay = [0.01,0]; r.target.gain = [1,0]; r.target.master = 1; r.current = r.target; r.playing = true; r.envelope = 1
        let b = render(r,frames:1024)
        XCTAssertEqual(b.floatChannelData![0][0],0)
        XCTAssertEqual(b.floatChannelData![0][480],0.5,accuracy:1e-4)
        XCTAssertTrue((0..<1024).allSatisfy { b.floatChannelData![1][$0] == 0 })
    }
    func testRepeatAndEnd() {
        let r = Renderer(); r.data = AudioData(left:Array(repeating:0.2,count:100),right:Array(repeating:0.2,count:100)); r.playing = true; r.target.processed = false
        _ = render(r,frames:256); XCTAssertFalse(r.playing); XCTAssertEqual(r.position,100/48000.0,accuracy:1e-9)
        r.position = 0; r.playing = true; r.target.repeating = true
        _ = render(r,frames:256); XCTAssertTrue(r.playing); XCTAssertLessThan(r.position,100/48000.0)
    }
    func testIdentifyPreservesCursorAndRoutes() {
        let r = Renderer(); r.position = 0.3; r.testChannel = 1
        let b = render(r,frames:2048)
        XCTAssertEqual(r.position,0.3); XCTAssertEqual(b.floatChannelData![0][1000],0)
        XCTAssertNotEqual(b.floatChannelData![1][1000],0)
    }
    func testLoadAndResample() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".wav")
        defer { try? FileManager.default.removeItem(at:url) }
        let f = AVAudioFormat(standardFormatWithSampleRate:44100,channels:1)!
        do {
            let file = try AVAudioFile(forWriting:url,settings:f.settings)
            let b = AVAudioPCMBuffer(pcmFormat:f,frameCapacity:4410)!; b.frameLength = 4410
            for i in 0..<4410 { b.floatChannelData![0][i] = Float(sin(Double(i)*0.1)*0.1) }
            try file.write(from:b)
        }
        let data = try AudioData.load(url)
        XCTAssertEqual(data.duration,0.1,accuracy:0.005); XCTAssertEqual(data.left,data.right)
    }
}
