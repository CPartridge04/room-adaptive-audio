import SwiftUI
import AVFoundation
import Accelerate

struct Measurement {
    let samples: [Float]
    let rate: Double
    let arrivals: [Double]
    let levels: [Double]
    let verification: Bool
    let date = Date()
    var differenceDB: Double { levels[1] - (levels[0] + levels[2])/2 }
    // L-R-L brackets the right event, cancelling constant latency and linear clock drift.
    var differenceMS: Double { (arrivals[1] - (arrivals[0]+arrivals[2])/2)*1000 }
    var gain: [Double] { [min(0,differenceDB), min(0,-differenceDB)] }
    var delay: [Double] { [max(0,differenceMS), max(0,-differenceMS)] }
}

enum CalibrationAnalysis {
    static func chirp(_ rate: Double) -> [Float] {
        let duration = 0.12
        return (0..<Int(rate*duration)).map { i in
            let t = Double(i)/rate
            let envelope = pow(sin(.pi*t/duration),2)
            return Float(envelope*sin(2 * .pi*(600*t + 0.5*(6000-600)/duration*t*t)))
        }
    }
    static func analyze(_ samples: [Float], rate: Double, verification: Bool) throws -> Measurement {
        guard samples.count > Int(rate*6), samples.allSatisfy({ $0.isFinite }), (samples.map { abs($0) }.max() ?? 1) < 0.98 else {
            throw AudioError.message("Recording is missing or clipped. Lower the Yeti gain and try again.")
        }
        let reference = chirp(rate)
        let count = samples.count-reference.count+1
        var correlation = [Float](repeating: 0, count: count)
        samples.withUnsafeBufferPointer { x in reference.withUnsafeBufferPointer { h in
            correlation.withUnsafeMutableBufferPointer { y in
                vDSP_conv(x.baseAddress!,1,h.baseAddress!,1,y.baseAddress!,1,vDSP_Length(count),vDSP_Length(reference.count))
            }
        }}
        var candidates = correlation.map { abs($0) }
        var indices = [Int]()
        for _ in 0..<3 {
            guard let index = candidates.indices.max(by: { candidates[$0] < candidates[$1] }) else { throw AudioError.message("No test signal detected.") }
            indices.append(index)
            for j in max(0,index-Int(rate))..<min(count,index+Int(rate)) { candidates[j] = 0 }
        }
        indices.sort()
        let gaps = [Double(indices[1]-indices[0])/rate,Double(indices[2]-indices[1])/rate]
        guard gaps.allSatisfy({ abs($0-2) < 0.15 }) else { throw AudioError.message("Could not identify all three test sounds. Check the input/output devices and try again.") }
        let noiseEnd = max(1,indices[0]-Int(rate*0.1))
        let noise = sqrt(samples.prefix(noiseEnd).reduce(0.0) { $0+Double($1*$1) }/Double(noiseEnd))
        var levels = [Double]()
        for index in indices {
            let segment = samples[index..<min(samples.count,index+reference.count)]
            let rms = sqrt(segment.reduce(0.0) { $0+Double($1*$1) }/Double(segment.count))
            let energy = reference.reduce(0.0) { $0+Double($1*$1) }
            let similarity = Double(abs(correlation[index])) / max(1e-12,sqrt(energy)*rms*sqrt(Double(segment.count)))
            guard rms > max(0.00001,noise*4), similarity > 0.15 else { throw AudioError.message("Test sound is too weak or unclear. Move the Yeti to the listening position, reduce background noise, or raise speaker volume slightly.") }
            levels.append(20*log10(max(1e-12,rms)))
        }
        guard abs(levels[0]-levels[2]) < 1.5 else { throw AudioError.message("The repeated left measurement changed too much. Keep the microphone and volume controls still, then retry.") }
        let result = Measurement(samples:samples,rate:rate,arrivals:indices.map { Double($0)/rate },levels:levels,verification:verification)
        guard abs(result.differenceMS) < 50, abs(result.differenceDB) < 24 else { throw AudioError.message("The mismatch is too large for automatic correction. Check routing and speaker placement.") }
        return result
    }
}

final class RecordingStore {
    let lock = NSLock()
    var samples = [Float]()
    func append(_ buffer: AVAudioPCMBuffer) {
        guard let data = buffer.floatChannelData else { return }
        lock.lock(); defer { lock.unlock() }
        let remaining = max(0,Int(buffer.format.sampleRate*9)-samples.count)
        samples.append(contentsOf: UnsafeBufferPointer(start:data[0],count:min(remaining,Int(buffer.frameLength))))
    }
    func snapshot() -> [Float] { lock.lock(); defer { lock.unlock() }; return samples }
}

final class CalibrationModel: ObservableObject {
    @Published var busy = false
    @Published var status = "Ready to measure"
    @Published var baseline: Measurement?
    @Published var verified: Measurement?
    @Published var latest: Measurement?
    private var recordingPlayer: AVAudioPlayer?
    private var engine: AVAudioEngine?
    private var player: AVAudioPlayerNode?
    private var finish: DispatchWorkItem?
    private var generation = UUID()
    private var observer: NSObjectProtocol?
    func cancel() {
        generation = UUID(); finish?.cancel(); finish = nil
        player?.stop()
        if let engine { engine.inputNode.removeTap(onBus:0); engine.stop() }
        engine = nil; player = nil
        if let observer { NotificationCenter.default.removeObserver(observer) }; observer = nil
        busy = false; status = "Test stopped. No new corrections applied."
    }
    func run(model: AppModel, verify: Bool) {
        guard !busy else { return }
        stopRecordingPlayback()
        model.pause(); model.engine.stop()
        busy = true; status = "Requesting microphone access…"
        let token = UUID(); generation = token
        AVCaptureDevice.requestAccess(for: .audio) { allowed in
            DispatchQueue.main.async {
                guard self.generation == token else { return }
                guard allowed else { self.busy = false; self.status = "Microphone access denied. Enable Audio Lab in System Settings → Privacy & Security → Microphone."; return }
                self.begin(model:model,verify:verify,token:token)
            }
        }
    }
    private func begin(model: AppModel, verify: Bool, token: UUID) {
        do {
            let engine = AVAudioEngine(), player = AVAudioPlayerNode()
            let input = engine.inputNode
            let inputFormat = input.outputFormat(forBus:0)
            guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else { throw AudioError.message("No microphone input. Select the Blue Yeti in macOS Sound settings.") }
            let store = RecordingStore()
            input.installTap(onBus:0,bufferSize:2048,format:inputFormat) { buffer,_ in store.append(buffer) }
            self.engine = engine; self.player = player
            engine.attach(player)
            let format = AVAudioFormat(standardFormatWithSampleRate:48000,channels:2)!
            engine.connect(player,to:engine.mainMixerNode,format:format)
            let buffer = AVAudioPCMBuffer(pcmFormat:format,frameCapacity:336000)!
            buffer.frameLength = 336000
            for channel in 0..<2 { buffer.floatChannelData![channel].initialize(repeating:0,count:336000) }
            let reference = CalibrationAnalysis.chirp(48000)
            let settings = DSPSettings(room:model.room)
            for (event,channel) in [0,1,0].enumerated() {
                let gain = verify ? settings.gain[channel] : 1
                let delay = verify ? settings.delay[channel] : 0
                let start = Int((1+Double(event)*2+delay)*48000)
                for i in reference.indices { buffer.floatChannelData![channel][start+i] = reference[i]*Float(0.2*model.master*gain) }
            }
            observer = NotificationCenter.default.addObserver(forName:.AVAudioEngineConfigurationChange,object:engine,queue:.main) { [weak self] _ in
                self?.cancel(); self?.status = "Audio device changed. Check routing and measure again."
            }
            player.scheduleBuffer(buffer)
            try engine.start(); player.play()
            status = verify ? "Recording corrected left → right → left…" : "Recording left → right → left…"
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.generation == token else { return }
                self.cancel(); self.busy = true; self.status = "Analysing recording…"
                let samples = store.snapshot(), rate = inputFormat.sampleRate
                let analysisToken = self.generation
                DispatchQueue.global(qos:.userInitiated).async {
                    let result = Result { try CalibrationAnalysis.analyze(samples,rate:rate,verification:verify) }
                    DispatchQueue.main.async {
                        guard self.generation == analysisToken else { return }
                        self.busy = false
                        switch result {
                        case .success(let measurement):
                            self.latest = measurement
                            if verify { self.verified = measurement } else { self.baseline = measurement; self.verified = nil }
                            self.status = verify ? "Verification complete. See the remaining mismatch in Measurements." : "Measurement complete. Apply the measured corrections, then verify."
                        case .failure(let error): self.status = error.localizedDescription
                        }
                    }
                }
            }
            finish = work; DispatchQueue.main.asyncAfter(deadline:.now()+7.5,execute:work)
        } catch { cancel(); status = error.localizedDescription }
    }
    func apply(_ model: AppModel) {
        guard let baseline else { return }
        model.edit { room in
            room.measuredGain = baseline.gain; room.measuredDelay = baseline.delay
            room.measuredCalibration = true; room.virtualHeadphones = false
            room.rotation = false; room.separation = false
        }
        model.processed = true
        status = "Measured corrections applied. Manual trims are preserved. Verify to measure the result."
    }
    func stopRecordingPlayback() { recordingPlayer?.stop(); recordingPlayer = nil }
    func playRecording(model: AppModel) {
        guard let latest else { return }
        model.pause()
        do {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("audio-lab-" + UUID().uuidString + ".wav")
            defer { try? FileManager.default.removeItem(at:url) }
            let format = AVAudioFormat(standardFormatWithSampleRate:latest.rate,channels:1)!
            let buffer = AVAudioPCMBuffer(pcmFormat:format,frameCapacity:AVAudioFrameCount(latest.samples.count))!
            buffer.frameLength = buffer.frameCapacity
            latest.samples.withUnsafeBufferPointer { buffer.floatChannelData![0].update(from:$0.baseAddress!,count:$0.count) }
            do { let file = try AVAudioFile(forWriting:url,settings:format.settings); try file.write(from:buffer) }
            recordingPlayer = try AVAudioPlayer(data:Data(contentsOf:url))
            recordingPlayer?.volume = Float(model.master)
            recordingPlayer?.play()
        } catch { status = error.localizedDescription }
    }
    func export() {
        guard let latest else { return }
        let panel = NSSavePanel(); panel.nameFieldStringValue = "Speaker measurement.wav"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let format = AVAudioFormat(standardFormatWithSampleRate:latest.rate,channels:1)!
            let buffer = AVAudioPCMBuffer(pcmFormat:format,frameCapacity:AVAudioFrameCount(latest.samples.count))!
            buffer.frameLength = buffer.frameCapacity
            latest.samples.withUnsafeBufferPointer { buffer.floatChannelData![0].update(from:$0.baseAddress!,count:$0.count) }
            let file = try AVAudioFile(forWriting:url,settings:format.settings)
            try file.write(from:buffer); status = "Recording exported."
        } catch { status = error.localizedDescription }
    }
}

struct CalibrationView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var calibration: CalibrationModel
    let measurements: Bool
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:20) {
                Text(measurements ? "Measurements" : "Calibrate your listening position").font(.largeTitle.bold())
                Text(calibration.status).foregroundStyle(.cyan).textSelection(.enabled)
                if !measurements {
                    Text("Choose Blue Yeti as the macOS input and the headphone/AUX connection as output. Place the Yeti at ear height at your seat, select omnidirectional mode, and keep its gain and speaker volume fixed. This records the first microphone channel.")
                    Button("Open Sound settings") { NSWorkspace.shared.open(URL(string:"x-apple.systempreferences:com.apple.Sound-Settings.extension")!) }
                    Text("The test uses three short 600–6000 Hz sweeps. Start at a comfortable speaker volume. It matches the measured sweep level and relative timing; it does not measure calibrated SPL or correct the subwoofer separately.").foregroundStyle(.secondary)
                    HStack {
                        Text("Test / playback master")
                        Slider(value:$model.master,in:0.01...0.5).frame(width:250)
                        Text(String(format:"%.1f dB",20*log10(max(0.00001,model.master))))
                    }.disabled(calibration.busy)
                    HStack {
                        Button("1. Measure speakers") { calibration.run(model:model,verify:false) }
                        Button("2. Apply automatic corrections") { calibration.apply(model) }.disabled(calibration.baseline == nil)
                        Button("3. Verify corrections") { calibration.run(model:model,verify:true) }.disabled(!model.room.measuredCalibration)
                    }.disabled(calibration.busy || model.loading)
                    if calibration.busy { Button("Cancel test") { calibration.cancel() } }
                    Toggle("Use measured corrections",isOn:Binding(get:{ model.room.measuredCalibration },set:{ value in
                        model.edit { r in r.measuredCalibration = value; if value { r.virtualHeadphones = false; r.rotation = false; r.separation = false } }
                    })).disabled(calibration.baseline == nil || calibration.busy)
                    Text("Applying calibration replaces geometry-based gain and timing and switches off virtual headphones and channel mixing. Original bypasses corrections. Manual trims remain additive. Re-measure after moving speakers or the microphone; verify again after changing trims.").font(.callout).foregroundStyle(.secondary)
                    HStack(alignment:.top) {
                        ForEach(0..<2,id:\.self) { i in SpeakerCard(model:model,index:i) }
                    }.disabled(calibration.busy)
                } else {
                    if let result = calibration.latest {
                        HStack {
                            Text(result.verification ? "Latest recording: corrected verification" : "Latest recording: uncorrected baseline").font(.headline)
                            Spacer()
                            Button("Play recording") { calibration.playRecording(model:model) }
                            Button("Stop recording playback") { calibration.stopRecordingPlayback() }
                            Button("Export recording (WAV)") { calibration.export() }
                        }
                        Text(result.date.formatted()).foregroundStyle(.secondary)
                        WaveformPlot(result:result).frame(height:210)
                        Text("Recorded waveform • seconds from recording start • markers show matched-sweep arrival estimates. Timing uses the strongest correlated path, which may include room reflections.").font(.caption).foregroundStyle(.secondary)
                        Grid(alignment:.leading,horizontalSpacing:28,verticalSpacing:12) {
                            GridRow { Text("Recorded event"); Text("Level (dBFS RMS)"); Text("Arrival in recording (ms)") }.bold()
                            ForEach(0..<3,id:\.self) { i in
                                GridRow {
                                    Text(["Left","Right","Left repeat"][i])
                                    Text(String(format:"%.2f",result.levels[i]))
                                    Text(String(format:"%.2f",result.arrivals[i]*1000))
                                }
                            }
                        }.monospacedDigit()
                        Divider()
                        if let baseline = calibration.baseline { comparison("Before correction",baseline) }
                        if let verified = calibration.verified { comparison("Last verification",verified) }
                        Text("Verification is a snapshot of settings at test time. Changing settings afterwards does not update the recorded result.").font(.caption).foregroundStyle(.secondary)
                    } else {
                        ContentPlaceholder()
                    }
                    Divider()
                    Text("Current correction settings").font(.title2)
                    Grid(alignment:.leading,horizontalSpacing:24,verticalSpacing:12) {
                        GridRow { Text("Speaker"); Text("Measured gain"); Text("Measured delay"); Text("Manual gain"); Text("Manual delay"); Text("Final gain / delay") }.bold()
                        ForEach(0..<2,id:\.self) { i in
                            let settings = DSPSettings(room:model.room)
                            GridRow {
                                Text(i == 0 ? "Left" : "Right")
                                Text(String(format:"%+.2f dB",model.room.measuredGain[i]))
                                Text(String(format:"%.2f ms",model.room.measuredDelay[i]))
                                Text(String(format:"%+.2f dB",model.room.speakers[i].trim))
                                Text(String(format:"%.2f ms",model.room.speakers[i].delayTrim))
                                Text(String(format:"%.2f dB / %.2f ms",20*log10(max(1e-12,settings.gain[i])),settings.delay[i]*1000))
                            }
                        }
                    }.font(.system(.callout,design:.monospaced))
                    Text(model.processed ? (model.room.measuredCalibration ? "Measured corrections enabled" : "Measured corrections disabled; final settings reflect the current listening mode") : "Original selected: playback bypasses corrections").foregroundStyle(.secondary)
                }
                Text("Recordings and calibration are kept for this app session. Export the recording before closing the app.").font(.caption).foregroundStyle(.secondary)
            }.padding(28)
        }
    }
    func comparison(_ title: String,_ m: Measurement) -> some View {
        HStack {
            Text(title).frame(width:160,alignment:.leading)
            Text(String(format:"Right − left level: %+.2f dB",m.differenceDB))
            Text(String(format:"Right − left arrival: %+.3f ms",m.differenceMS))
        }.font(.system(.body,design:.monospaced))
    }
}
struct ContentPlaceholder: View {
    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            Image(systemName:"waveform").font(.largeTitle)
            Text("No recording yet").font(.title2)
            Text("Run Measure speakers on the Calibrate page to see real microphone data here.").foregroundStyle(.secondary)
        }.frame(maxWidth:.infinity,minHeight:220,alignment:.leading)
    }
}
struct WaveformPlot: View {
    let result: Measurement
    var body: some View {
        Canvas { context,size in
            let n = result.samples.count, width = max(1,Int(size.width))
            let scale = max(0.001,Double(result.samples.map { abs($0) }.max() ?? 1))
            var path = Path()
            for x in 0..<width {
                let lo = x*n/width, hi = min(n,max(lo+1,(x+1)*n/width))
                guard lo < n else { continue }
                let segment = result.samples[lo..<hi]
                let top = Double(segment.max() ?? 0), bottom = Double(segment.min() ?? 0)
                path.move(to:CGPoint(x:Double(x),y:size.height/2-top/scale*size.height*0.43))
                path.addLine(to:CGPoint(x:Double(x),y:size.height/2-bottom/scale*size.height*0.43))
            }
            context.stroke(path,with:.color(.cyan),lineWidth:1)
            let duration = Double(n)/result.rate
            for (i,t) in result.arrivals.enumerated() {
                let x = t/duration*size.width
                var marker = Path(); marker.move(to:CGPoint(x:x,y:0)); marker.addLine(to:CGPoint(x:x,y:size.height-20))
                context.stroke(marker,with:.color(.orange),style:StrokeStyle(lineWidth:1,dash:[4,4]))
                context.draw(Text(["L","R","L repeat"][i]).font(.caption).foregroundColor(.orange),at:CGPoint(x:x+22,y:12))
            }
            for second in 0...Int(duration) {
                context.draw(Text("\(second)s").font(.caption).foregroundColor(.secondary),at:CGPoint(x:Double(second)/duration*size.width+8,y:size.height-8))
            }
        }.padding(12).background(.primary.opacity(0.04),in:RoundedRectangle(cornerRadius:12))
    }
}
