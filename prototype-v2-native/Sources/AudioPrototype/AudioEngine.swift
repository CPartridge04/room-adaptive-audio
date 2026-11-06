import AVFoundation
import Accelerate
import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct AudioData {
    let left: [Float]; let right: [Float]
    var duration: Double { Double(left.count) / 48000 }
    static func load(_ url: URL) throws -> AudioData {
        let file = try AVAudioFile(forReading: url)
        guard (1...2).contains(file.processingFormat.channelCount) else { throw AudioError.message("Choose a mono or stereo music file.") }
        let duration = Double(file.length) / file.processingFormat.sampleRate
        guard duration > 0 && duration <= 900 else { throw AudioError.message("This in-memory prototype accepts files up to 15 minutes long.") }
        guard let input = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)) else { throw AudioError.message("Cannot allocate audio memory.") }
        try file.read(into: input)
        let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: file.processingFormat.channelCount)!
        guard let converter = AVAudioConverter(from: file.processingFormat, to: format), let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(ceil(duration*48000)+4096)) else { throw AudioError.message("Cannot convert this audio format.") }
        var supplied = false; var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, state in
            if supplied { state.pointee = .endOfStream; return nil }
            supplied = true; state.pointee = .haveData; return input
        }
        if let error { throw error }
        guard status != .error, let channels = output.floatChannelData, output.frameLength > 0 else { throw AudioError.message("The file could not be decoded.") }
        let n = Int(output.frameLength)
        let l = Array(UnsafeBufferPointer(start: channels[0], count: n))
        let r = format.channelCount == 1 ? l : Array(UnsafeBufferPointer(start: channels[1], count: n))
        guard l.allSatisfy({ $0.isFinite }), r.allSatisfy({ $0.isFinite }) else { throw AudioError.message("The file contains invalid audio samples.") }
        return AudioData(left: l, right: r)
    }
}
enum AudioError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let s) = self { return s }; return nil }
}

final class Renderer {
    let lock = NSLock()
    var data: AudioData?
    var target = DSPSettings()
    var current = DSPSettings()
    var position = 0.0; var playing = false; var hasLooped = false
    var wet = 1.0; var envelope = 0.0
    var testChannel = -1; var testFrame = 0
    var peak = [0.0,0.0]; var clipped = false
    var earBlend = 0.0
    var earTaps = Array(repeating: Array(repeating: 0.0, count: EarFilters.size), count: 4)
    var inputHistory = Array(repeating: Array(repeating: 0.0, count: EarFilters.size*2), count: 2)
    var outputHistory = Array(repeating: Array(repeating: 0.0, count: 16384), count: 2)
    var inputIndex = 0; var outputIndex = 0
    func resetFilters() {
        inputHistory = Array(repeating: Array(repeating: 0, count: EarFilters.size*2), count: 2)
        outputHistory = Array(repeating: Array(repeating: 0, count: 16384), count: 2)
        inputIndex = 0; outputIndex = 0
    }
    func filtered(_ speaker: Int, _ taps: [[Double]]) -> Double {
        var result = 0.0
        for channel in 0..<2 {
            var dot = 0.0
            inputHistory[channel].withUnsafeBufferPointer { history in
                taps[speaker*2+channel].withUnsafeBufferPointer { filter in
                    vDSP_dotprD(history.baseAddress!+inputIndex,1,filter.baseAddress!,1,&dot,vDSP_Length(EarFilters.size))
                }
            }
            result += dot
        }
        return result
    }
    func sample(_ channel: Int, _ t: Double) -> Double {
        guard let data else { return 0 }
        let values = channel == 0 ? data.left : data.right
        guard !values.isEmpty else { return 0 }
        var p = t * 48000
        if p < -0.000001 {
            guard target.repeating && hasLooped else { return 0 }
            p += ceil(-p/Double(values.count))*Double(values.count)
        } else { p = max(0,p) }
        if target.repeating { p.formTruncatingRemainder(dividingBy: Double(values.count)) }
        guard p < Double(values.count) else { return 0 }
        let i = Int(p), j = i+1 < values.count ? i+1 : (target.repeating ? 0 : i)
        return Double(values[i]) + (Double(values[j])-Double(values[i]))*(p-Double(i))
    }
    func render(_ count: Int, _ list: UnsafeMutablePointer<AudioBufferList>) -> OSStatus {
        let buffers = UnsafeMutableAudioBufferListPointer(list)
        for b in buffers { if let p = b.mData { memset(p,0,Int(b.mDataByteSize)) } }
        guard lock.try() else { return noErr } // never wait on the audio thread
        defer { lock.unlock() }
        guard buffers.count >= 2, let lp = buffers[0].mData?.assumingMemoryBound(to: Float.self), let rp = buffers[1].mData?.assumingMemoryBound(to: Float.self) else { return noErr }
        peak[0] *= 0.9; peak[1] *= 0.9
        let nextTaps = target.earFilters?.taps ?? earTaps
        let smoothing = 0.02 * 48000.0
        defer {
            let blend = 1-exp(-Double(count)/smoothing)
            for j in 0..<4 { for k in 0..<EarFilters.size {
                earTaps[j][k] += (nextTaps[j][k]-earTaps[j][k])*blend
            } }
        }
        for frame in 0..<count {
            if testChannel >= 0 {
                let t = Double(testFrame)/48000
                let fade = min(1,min(t/0.025,(0.8-t)/0.025))
                let v = Float(sin(t*2 * .pi * (testChannel == 0 ? 440 : 660)) * max(0,fade) * 0.1 * target.master)
                if testChannel == 0 { lp[frame] = v } else { rp[frame] = v }
                testFrame += 1
                if testFrame >= 38400 { testChannel = -1 }
                continue
            }
            guard playing, let data else { continue }
            envelope += (1-envelope)*0.002
            wet += ((target.processed ? 1.0 : 0.0)-wet)*0.002
            current.master += (target.master-current.master)*0.002
            earBlend += ((target.earFilters == nil ? 0.0 : 1.0)-earBlend)*0.002
            inputIndex = (inputIndex+EarFilters.size-1)%EarFilters.size
            for channel in 0..<2 {
                let value = sample(channel,position)
                inputHistory[channel][inputIndex] = value
                inputHistory[channel][inputIndex+EarFilters.size] = value
            }
            let filterBlend = 1-exp(-Double(frame+1)/smoothing)
            for i in 0..<2 {
                current.gain[i] += (target.gain[i]-current.gain[i])*0.002
                current.delay[i] += (target.delay[i]-current.delay[i])*0.0005
                current.left[i] += (target.left[i]-current.left[i])*0.002
                current.right[i] += (target.right[i]-current.right[i])*0.002
                current.cancel[i] += (target.cancel[i]-current.cancel[i])*0.002
                current.crossDelay[i] += (target.crossDelay[i]-current.crossDelay[i])*0.002
                let t = position-current.delay[i]
                let direct = sample(0,t)*current.left[i] + sample(1,t)*current.right[i]
                let opposite = sample(1,t-current.crossDelay[i])*current.left[i] + sample(0,t-current.crossDelay[i])*current.right[i]
                var virtual = 0.0
                if earBlend > 0.00001 {
                    let before = filtered(i,earTaps), after = filtered(i,nextTaps)
                    outputHistory[i][outputIndex] = before+(after-before)*filterBlend
                    let read = Double(outputIndex)-current.delay[i]*48000
                    let lower = Int(floor(read)), fraction = read-floor(read)
                    let a = outputHistory[i][(lower+32768)%16384]
                    let b = outputHistory[i][(lower+32769)%16384]
                    virtual = a+(b-a)*fraction
                } else { outputHistory[i][outputIndex] = 0 }
                let legacy = direct-current.cancel[i]*opposite
                let processed = (legacy*(1-earBlend)+virtual*earBlend)*current.gain[i]
                let v = ((1-wet)*sample(i,position)+wet*processed)*current.master*envelope
                if abs(v)>0.98 { clipped = true }
                let limited = min(0.98,max(-0.98,v))
                peak[i] = max(peak[i],abs(limited))
                if i == 0 { lp[frame] = Float(limited) } else { rp[frame] = Float(limited) }
            }
            outputIndex = (outputIndex+1)%16384
            position += 1/48000.0
            if target.repeating && position >= data.duration { position -= data.duration; hasLooped = true }
            if !target.repeating && position >= data.duration + (target.processed ? max(current.delay[0],current.delay[1])+(target.earFilters == nil ? 0.001 : Double(EarFilters.size)/48000) : 0) {
                position = data.duration; playing = false; envelope = 0
            }
        }
        return noErr
    }
}

final class AppModel: ObservableObject {
    @Published var room: Room = { var room = Room(); room.virtualHeadphones = true; return room }() { didSet { update() } }
    @Published var processed = true { didSet { update() } }
    @Published var master = 0.15 { didSet { update() } }
    @Published var repeating = false { didSet { update() } }
    @Published var position = 0.0
    @Published var duration = 0.0
    @Published var playing = false
    @Published var filename = "Load a music file to begin"
    @Published var loading = false
    @Published var error: String?
    @Published var peaks = [0.0,0.0]
    @Published var clipped = false
    let renderer = Renderer()
    let engine = AVAudioEngine()
    var source: AVAudioSourceNode!
    var timer: Timer?
    var notification: NSObjectProtocol?
    init() {
        let r = renderer
        source = AVAudioSourceNode(format: AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!) { _,_,count,list in r.render(Int(count),list) }
        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!)
        update()
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.renderer.lock.lock()
            self.position = min(self.duration,self.renderer.position); self.playing = self.renderer.playing
            self.peaks = self.renderer.peak; self.clipped = self.renderer.clipped
            self.renderer.lock.unlock()
        }
        notification = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.pause(); self.engine.stop()
            self.error = "The audio output changed. Check macOS Sound settings, then press Play to resume."
        }
    }
    func update() {
        var settings = DSPSettings(room: room)
        settings.processed = processed; settings.master = master; settings.repeating = repeating
        renderer.lock.lock(); renderer.target = settings; renderer.lock.unlock()
    }
    func edit(_ body: (inout Room) -> Void) { var value = room; body(&value); value.constrain(); room = value }
    func startEngine() throws {
        if !engine.isRunning { engine.prepare(); try engine.start() }
    }
    func play() {
        guard duration > 0 else { return }
        do {
            try startEngine()
            renderer.lock.lock()
            if renderer.position >= duration { renderer.position = 0; renderer.hasLooped = false; renderer.resetFilters() }
            renderer.testChannel = -1; renderer.playing = true; renderer.envelope = 0
            renderer.lock.unlock()
        } catch { self.error = error.localizedDescription }
    }
    func pause() { renderer.lock.lock(); renderer.playing = false; renderer.testChannel = -1; renderer.envelope = 0; renderer.lock.unlock(); playing = false }
    func stop() { pause(); seek(0); renderer.lock.lock(); renderer.clipped = false; renderer.lock.unlock() }
    func seek(_ value: Double) { renderer.lock.lock(); renderer.position = finiteClamp(value,0,duration); renderer.hasLooped = false; renderer.envelope = 0; renderer.resetFilters(); renderer.lock.unlock(); position = value }
    func test(_ channel: Int) {
        do { try startEngine(); pause(); renderer.lock.lock(); renderer.testChannel = channel; renderer.testFrame = 0; renderer.lock.unlock() }
        catch { self.error = error.localizedDescription }
    }
    func loadEarCheck() {
        pause()
        var left = [Float](), right = [Float]()
        for frame in 0..<384000 {
            let second = Double(frame)/48000
            let local = second-floor(second)
            let fade = max(0,min(1,min(local/0.03,(0.8-local)/0.03)))
            let isLeft = Int(second)%2 == 0
            let tone = Float(0.12*fade*sin(second*2 * .pi*(isLeft ? 700 : 1100)))
            left.append(isLeft ? tone : 0); right.append(isLeft ? 0 : tone)
        }
        renderer.lock.lock()
        renderer.data = AudioData(left:left,right:right); renderer.position = 0
        renderer.hasLooped = false; renderer.clipped = false; renderer.resetFilters()
        renderer.lock.unlock()
        duration = 8; position = 0
        filename = "Ear check: low tone LEFT ear, high tone RIGHT ear"
    }
    func load() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.audio]; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        pause(); loading = true
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try AudioData.load(url) }
            DispatchQueue.main.async {
                self.loading = false
                switch result {
                case .success(let data):
                    self.renderer.lock.lock(); self.renderer.data = data; self.renderer.position = 0; self.renderer.hasLooped = false; self.renderer.clipped = false; self.renderer.resetFilters(); self.renderer.lock.unlock()
                    self.duration = data.duration; self.position = 0; self.filename = url.lastPathComponent
                case .failure(let error): self.error = error.localizedDescription
                }
            }
        }
    }
}
