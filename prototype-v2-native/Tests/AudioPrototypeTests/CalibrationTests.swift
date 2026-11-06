import XCTest
@testable import AudioPrototype
final class CalibrationTests: XCTestCase {
    func recording(rightGain: Float = 0.5, rightDelay: Double = 0.004) -> [Float] {
        let rate = 24000.0
        var samples = [Float](repeating:0,count:Int(7*rate))
        let chirp = CalibrationAnalysis.chirp(rate)
        // Common latency plus linear drift; both must cancel from the relative result.
        for event in 0..<3 {
            let start = Int((1.1+Double(event)*2.0002+(event == 1 ? rightDelay : 0))*rate)
            for i in chirp.indices { samples[start+i] = chirp[i]*0.2*(event == 1 ? rightGain : 1) }
        }
        return samples
    }
    func testDetectsRelativeLevelAndTimingDespiteLatencyAndDrift() throws {
        let m = try CalibrationAnalysis.analyze(recording(),rate:24000,verification:false)
        XCTAssertEqual(m.differenceDB,-6.0206,accuracy:0.02)
        XCTAssertEqual(m.differenceMS,4,accuracy:0.05)
        XCTAssertEqual(m.gain[0],-6.0206,accuracy:0.02)
        XCTAssertEqual(m.gain[1],0,accuracy:0.01)
        XCTAssertEqual(m.delay[0],4,accuracy:0.05)
        XCTAssertEqual(m.delay[1],0,accuracy:0.05)
    }
    func testCorrectedSignalsMatch() throws {
        let m = try CalibrationAnalysis.analyze(recording(rightGain:1,rightDelay:0),rate:24000,verification:true)
        XCTAssertEqual(m.differenceDB,0,accuracy:0.01)
        XCTAssertEqual(m.differenceMS,0,accuracy:0.05)
    }
    func testRejectsSilenceAndClipping() {
        XCTAssertThrowsError(try CalibrationAnalysis.analyze([Float](repeating:0,count:168000),rate:24000,verification:false))
        var samples = recording(); samples[0] = 1
        XCTAssertThrowsError(try CalibrationAnalysis.analyze(samples,rate:24000,verification:false))
    }
    func testMeasuredCorrectionsReplaceGeometryAndPreserveTrims() {
        var room = Room(); room.measuredCalibration = true
        room.measuredGain = [-6,0]; room.measuredDelay = [4,0]
        room.speakers[0].trim = 1; room.speakers[0].delayTrim = 2
        let settings = DSPSettings(room:room)
        XCTAssertEqual(20*log10(settings.gain[0]),-5,accuracy:0.001)
        XCTAssertEqual(settings.delay[0],0.006,accuracy:0.000001)
    }
}
