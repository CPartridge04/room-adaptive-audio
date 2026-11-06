import SwiftUI

struct NumberControl: View {
    let label: String
    @Binding var value: Double
    var range: ClosedRange<Double>
    var unit: String
    var slider = false
    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text(label).foregroundStyle(.secondary)
                Spacer()
                TextField(label, value: $value, format: .number.precision(.fractionLength(2)))
                    .multilineTextAlignment(.trailing).textFieldStyle(.roundedBorder).frame(width: 72)
                    .accessibilityLabel("\(label), \(unit)")
                Text(unit).font(.caption).foregroundStyle(.secondary).frame(width: 24, alignment: .leading)
            }
            if slider { Slider(value: $value, in: range).accessibilityLabel(label) }
        }
    }
}
struct Dashboard: View {
    @StateObject var model = AppModel()
    @StateObject var calibration = CalibrationModel()
    @State var page = 0
    func roomValue(_ path: WritableKeyPath<Room,Double>) -> Binding<Double> {
        Binding(get: { model.room[keyPath:path] }, set: { v in model.edit { $0[keyPath:path] = v } })
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "waveform.path").font(.title).foregroundStyle(.cyan)
                VStack(alignment: .leading) {
                    Text("Audio / spatial listening lab").font(.title2.bold())
                    Text("Speaker calibration • Stereo output • v0.4").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(model.playing ? "PLAYING" : "READY").font(.caption.monospaced().bold()).foregroundStyle(model.playing ? .green : .secondary)
            }.padding(20)
            Picker("Page", selection: $page) {
                Text("Listen").tag(0); Text("Calibrate").tag(1); Text("Measurements").tag(2)
            }.pickerStyle(.segmented).padding(.horizontal, 20).disabled(calibration.busy)
            Divider()
            if page == 0 {
            HStack(alignment: .top, spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("SPEAKERS").font(.caption.bold()).foregroundStyle(.secondary)
                        Picker("Layout", selection: Binding(get: { model.room.count }, set: { v in model.edit { $0.count = v } })) {
                            Text("2 speakers").tag(2); Text("4 speakers").tag(4)
                        }.pickerStyle(.segmented)
                        ForEach(0..<model.room.count, id: \.self) { i in SpeakerCard(model: model, index: i) }
                    }.padding(16)
                }.frame(width: 290)
                Divider()
                VStack(spacing: 12) {
                    HStack {
                        Text("ROOM").font(.caption.bold()).foregroundStyle(.secondary)
                        Spacer()
                        Text("Drag speakers, listener or direction handle").font(.caption).foregroundStyle(.secondary)
                    }
                    HStack {
                        NumberControl(label: "Width", value: roomValue(\.width), range: 1...30, unit: "m")
                        NumberControl(label: "Length", value: roomValue(\.length), range: 1...30, unit: "m")
                    }
                    RoomView(model: model)
                    HStack {
                        Label("Left ear", systemImage: "circle.fill").foregroundStyle(.cyan)
                        Label("Right ear", systemImage: "circle.fill").foregroundStyle(.orange)
                        Spacer()
                        Text("0° ↑ • x → • y ↓").foregroundStyle(.secondary)
                    }.font(.caption)
                    if model.room.count == 4 {
                        Text("4-speaker planning view. Rear speakers are calculated only; playback uses the front pair. Front playback delays are aligned to that pair.")
                            .font(.caption).foregroundStyle(.orange).padding(10).background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    }
                    GraphView(model: model).frame(height: 105)
                }.padding(18).frame(minWidth: 430)
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 15) {
                        Text("LISTENER").font(.caption.bold()).foregroundStyle(.secondary)
                        NumberControl(label: "Position x", value: roomValue(\.x), range: 0...model.room.width, unit: "m")
                        NumberControl(label: "Position y", value: roomValue(\.y), range: 0...model.room.length, unit: "m")
                        NumberControl(label: "Ear height", value: roomValue(\.height), range: 0...3, unit: "m")
                        NumberControl(label: "Ear spacing", value: roomValue(\.earSpacing), range: 0.1...0.3, unit: "m")
                        NumberControl(label: "Direction", value: roomValue(\.heading), range: 0...360, unit: "°", slider: true)
                        Divider()
                        Text("LIVE PROCESSING").font(.caption.bold()).foregroundStyle(.secondary)
                        Toggle("Virtual headphones (experimental)", isOn: $model.room.virtualHeadphones).disabled(model.room.measuredCalibration)
                        if model.room.measuredCalibration { Text("Measured level and timing calibration active. Geometry gain and delay are replaced.").font(.caption).foregroundStyle(.cyan) }
                        if model.room.virtualHeadphones {
                            Text("Match your real head position and direction to the diagram. Keep the speakers at their entered positions. Both outputs are needed.").font(.caption).foregroundStyle(.secondary)
                            Text("Geometry-based ear separation is active. Room reflections and your head shape are not calibrated; this is an approximation, not guaranteed headphone sound.").font(.caption).foregroundStyle(.secondary)
                            Button("Load ear check") { model.loadEarCheck() }
                            Text("Then press Play: lower tone should favour your left ear; higher tone your right. Turn yourself and update the arrow together.").font(.caption).foregroundStyle(.secondary)
                            let a = model.room.heading * Double.pi / 180
                            let dx = model.room.speakers[1].x-model.room.speakers[0].x
                            let dy = model.room.speakers[1].y-model.room.speakers[0].y
                            if abs(dx*cos(a)+dy*sin(a)) < 0.25*max(0.001,hypot(dx,dy)) {
                                Text("Limited ear separation at this angle. The two speakers cannot independently control your ears reliably here.").font(.caption).foregroundStyle(.orange)
                            }
                        }
                        Group {
                        Toggle("Distance volume compensation", isOn: $model.room.volume)
                        Toggle("Arrival-time alignment", isOn: $model.room.alignment)
                        Toggle("Head-relative stereo", isOn: $model.room.rotation)
                        Toggle("Experimental ear separation", isOn: $model.room.separation)
                        }.disabled(model.room.virtualHeadphones)
                        Text(model.room.virtualHeadphones ? "Virtual headphones handles path gain and timing itself. The four controls above apply only when it is off. Original bypasses all processing." : "Head-relative stereo rotates the channel mix with your direction. Ear separation independently adds experimental opposite-channel subtraction. Original bypasses both.").font(.caption).foregroundStyle(.secondary)
                        Text("Alignment adds delay to the nearer speaker. Equal distances need no added delay, even when both speakers are farther away.").font(.caption).foregroundStyle(.secondary)
                        Divider()
                        Text("OUTPUT").font(.caption.bold()).foregroundStyle(.secondary)
                        Text("Mac default stereo output").font(.headline)
                        Text("Connect Z407 via AUX and choose the corresponding output in macOS Sound settings. Channels 1 / 2 feed front left / right.").font(.caption).foregroundStyle(.secondary)
                        Button("Open Sound settings") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension")!) }
                        Button("Reset manual adjustments") { model.edit { r in for i in r.speakers.indices { r.speakers[i].trim = 0; r.speakers[i].delayTrim = 0 } } }
                        Text("Free-field model • 343 m/s\nGain reference: 2 m • Gain cap: +18 dB\nDelay trims: 0–100 ms • Total cap: 200 ms").font(.caption).foregroundStyle(.secondary)
                    }.padding(16)
                }.frame(width: 280)
            }
            Divider()
            transport
            } else {
                CalibrationView(model: model, calibration: calibration, measurements: page == 2)
            }
        }
        .frame(minWidth: 1080, minHeight: 760)
        .background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: page) { _ in calibration.stopRecordingPlayback() }
        .alert("Audio", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) { Button("OK") { model.error = nil } } message: { Text(model.error ?? "") }
    }
    var transport: some View {
        VStack(spacing: 10) {
            HStack {
                Button(action: model.load) { Label(model.loading ? "Loading…" : "Load music", systemImage: "folder") }.disabled(model.loading)
                Text(model.filename).font(.callout).lineLimit(1)
                Spacer()
                Picker("Comparison", selection: $model.processed) { Text("Original").tag(false); Text("Processed").tag(true) }.pickerStyle(.segmented).labelsHidden().frame(width: 220)
                Toggle("Repeat", isOn: $model.repeating).toggleStyle(.checkbox)
            }
            HStack(spacing: 14) {
                Button(action: model.play) { Image(systemName: "play.fill") }.disabled(model.duration == 0 || model.loading)
                Button(action: model.pause) { Image(systemName: "pause.fill") }.disabled(!model.playing)
                Button(action: model.stop) { Image(systemName: "stop.fill") }
                Text(time(model.position)).monospacedDigit().frame(width: 45)
                Slider(value: Binding(get: { model.position }, set: model.seek), in: 0...max(0.01,model.duration)).disabled(model.duration == 0).accessibilityLabel("Playback position")
                Text(time(model.duration)).monospacedDigit().frame(width: 45)
                Image(systemName: "speaker.wave.2")
                Slider(value: $model.master, in: 0...1).frame(width: 105).accessibilityLabel("Master volume")
                Text(model.master > 0 ? String(format: "%.1f dB",20*log10(model.master)) : "−∞ dB").font(.caption.monospaced()).frame(width: 64)
                VStack(spacing: 3) { meter(0); meter(1) }.frame(width: 105)
            }
            HStack {
                Text(model.processed ? "Processed • live controls active" : "Original stereo • spatial processing and speaker trims bypassed").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(model.clipped ? "Peak limit reached — reduce master or trims" : "Output peak meters • master starts at −16.5 dB")
                    .font(.caption).foregroundStyle(model.clipped ? Color.orange : Color.secondary)
            }
        }.padding(16)
    }
    func meter(_ i: Int) -> some View {
        HStack(spacing: 4) { Text(i == 0 ? "L" : "R").font(.caption2); ProgressView(value: min(1,model.peaks[i])).tint(model.clipped ? .orange : .green) }
    }
    func time(_ seconds: Double) -> String { String(format: "%d:%02d",Int(seconds)/60,Int(seconds)%60) }
}
struct SpeakerCard: View {
    @ObservedObject var model: AppModel
    let index: Int
    func field(_ path: WritableKeyPath<Speaker,Double>) -> Binding<Double> {
        Binding(get: { model.room.speakers[index][keyPath:path] }, set: { v in model.edit { $0.speakers[index][keyPath:path] = v } })
    }
    var body: some View {
        let s = model.room.speakers[index], c = model.room.calculations()[index]
        VStack(alignment: .leading, spacing: 9) {
            HStack { Text(s.name).font(.headline); Spacer(); Text(index < 2 ? "OUT \(index+1)" : "PLAN ONLY").font(.caption2).foregroundStyle(index < 2 ? .cyan : .orange) }
            NumberControl(label: "x", value: field(\.x), range: 0...model.room.width, unit: "m")
            NumberControl(label: "y", value: field(\.y), range: 0...model.room.length, unit: "m")
            NumberControl(label: "Height", value: field(\.z), range: 0...5, unit: "m")
            Text(String(format: "Distance %.2f m · ears %.2f / %.2f m",c.distance,c.leftEar,c.rightEar)).font(.caption.monospaced()).foregroundStyle(.secondary)
            HStack { Text("Auto gain / added delay"); Spacer(); Text(String(format: "%+.2f dB / %.2f ms",c.automaticDB,c.automaticMS)) }.font(.caption.monospaced())
            Text(String(format: "Sound travel %.3f ms · added %.3f ms", c.distance / 343 * 1000, c.automaticMS)).font(.caption.monospaced()).foregroundStyle(.secondary)
            NumberControl(label: "Gain trim", value: field(\.trim), range: -24...12, unit: "dB", slider: true)
            NumberControl(label: "Delay trim", value: field(\.delayTrim), range: 0...100, unit: "ms", slider: true)
            HStack { Button("Reset gain") { model.edit { $0.speakers[index].trim = 0 } }; Button("Reset delay") { model.edit { $0.speakers[index].delayTrim = 0 } } }.font(.caption)
            Text(String(format: "Final %+.2f dB · %.2f ms",c.finalDB,c.finalMS)).font(.callout.monospaced().bold()).foregroundStyle(.cyan)
            if abs(c.finalDB-(c.automaticDB+s.trim))>0.001 || abs(c.finalMS-(c.automaticMS+s.delayTrim))>0.001 { Text("Final value capped").font(.caption).foregroundStyle(.orange) }
            if model.room.count == 4 && index < 2 {
                Text(String(format: "Stereo playback delay: %.2f ms",model.room.calculations(2)[index].finalMS)).font(.caption).foregroundStyle(.secondary)
            }
            if index < 2 {
                if model.room.virtualHeadphones {
                    Text("Virtual headphones: both ear paths filtered").font(.caption).foregroundStyle(.secondary)
                } else {
                let mix = DSPSettings(room: model.room)
                Text(String(format: "Stereo mix: L %.0f%% · R %.0f%%", mix.left[index] * 100, mix.right[index] * 100)).font(.caption.monospaced()).foregroundStyle(.secondary)
                }
            }
            HStack {
                Toggle("Mute", isOn: $model.room.speakers[index].mute).toggleStyle(.button)
                Toggle("Solo", isOn: $model.room.speakers[index].solo).toggleStyle(.button)
                Button("Identify") { model.test(index) }
            }.disabled(index >= 2)
        }.padding(12).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
    }
}
struct RoomView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        GeometryReader { geometry in
            let r = model.room
            let scale = min((geometry.size.width-64)/r.width,(geometry.size.height-64)/r.length)
            let ox = (geometry.size.width-r.width*scale)/2, oy = (geometry.size.height-r.length*scale)/2
            let listener = CGPoint(x: ox+r.x*scale,y: oy+r.y*scale)
            let angle = r.heading * .pi / 180
            let handle = CGPoint(x: listener.x+sin(angle)*48,y: listener.y-cos(angle)*48)
            ZStack(alignment: .topLeading) {
                Canvas { context, size in
                    let rect = CGRect(x: ox,y: oy,width: r.width*scale,height: r.length*scale)
                    context.fill(Path(rect), with: .color(.primary.opacity(0.035)))
                    context.stroke(Path(rect), with: .color(.secondary.opacity(0.6)), lineWidth: 2)
                    for x in 0...Int(r.width) {
                        var p = Path(); p.move(to: CGPoint(x: ox+Double(x)*scale,y: oy)); p.addLine(to: CGPoint(x: ox+Double(x)*scale,y: oy+r.length*scale)); context.stroke(p,with:.color(.secondary.opacity(0.12)),lineWidth:1)
                    }
                    for y in 0...Int(r.length) {
                        var p = Path(); p.move(to: CGPoint(x: ox,y: oy+Double(y)*scale)); p.addLine(to: CGPoint(x: ox+r.width*scale,y: oy+Double(y)*scale)); context.stroke(p,with:.color(.secondary.opacity(0.12)),lineWidth:1)
                    }
                    for s in r.speakers.prefix(r.count) {
                        var p = Path(); p.move(to: CGPoint(x: ox+s.x*scale,y: oy+s.y*scale)); p.addLine(to: listener)
                        context.stroke(p,with:.color(s.id < 2 ? .cyan.opacity(0.35) : .orange.opacity(0.3)),style:StrokeStyle(lineWidth:1,dash:[5,4]))
                    }
                    var arrow = Path(); arrow.move(to: listener); arrow.addLine(to: handle)
                    context.stroke(arrow,with:.color(.primary),lineWidth:2)
                    for (i,ear) in r.ears.enumerated() {
                        let point = CGPoint(x: ox+ear.0*scale,y: oy+ear.1*scale)
                        context.fill(Path(ellipseIn: CGRect(x: point.x-4,y: point.y-4,width: 8,height: 8)),with:.color(i == 0 ? .cyan : .orange))
                    }
                }
                ForEach(Array(r.speakers.prefix(r.count))) { s in
                    VStack(spacing: 1) { Image(systemName:"hifispeaker.fill").font(.title3); Text("\(s.id+1)").font(.caption2.bold()) }
                        .foregroundStyle(s.id < 2 ? Color.cyan : .orange).frame(width: 30,height: 38).contentShape(Rectangle())
                        .position(x:ox+s.x*scale,y:oy+s.y*scale)
                        .gesture(DragGesture(minimumDistance:0,coordinateSpace:.named("room")).onChanged { v in model.edit { $0.speakers[s.id].x = (v.location.x-ox)/scale; $0.speakers[s.id].y = (v.location.y-oy)/scale } })
                        .accessibilityLabel("Drag \(s.name)")
                }
                Circle().stroke(.primary,lineWidth:2).background(Circle().fill(.primary.opacity(0.08))).frame(width: 32,height: 32).contentShape(Circle()).position(listener)
                    .gesture(DragGesture(minimumDistance:0,coordinateSpace:.named("room")).onChanged { v in model.edit { $0.x = (v.location.x-ox)/scale; $0.y = (v.location.y-oy)/scale } }).accessibilityLabel("Drag listener")
                Image(systemName:"arrowtriangle.up.fill").rotationEffect(.degrees(r.heading)).frame(width:28,height:28).contentShape(Circle()).position(handle)
                    .gesture(DragGesture(minimumDistance:0,coordinateSpace:.named("room")).onChanged { v in
                        var degrees = atan2(v.location.x-listener.x, -(v.location.y-listener.y))*180 / .pi
                        if degrees < 0 { degrees += 360 }; model.edit { $0.heading = degrees }
                    }).accessibilityLabel("Rotate listener direction")
            }.coordinateSpace(name:"room")
        }.frame(minHeight: 270).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
    }
}
struct GraphView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        let delayScale = max(5,model.room.calculations().map { $0.finalMS }.max() ?? 0)
        VStack(alignment: .leading, spacing: 7) {
            Text("CALCULATED GAIN & DELAY").font(.caption2.bold()).foregroundStyle(.secondary)
            HStack(alignment: .bottom, spacing: 12) {
                ForEach(Array(model.room.calculations().enumerated()), id: \.offset) { i,c in
                    VStack(spacing: 4) {
                        GeometryReader { g in
                            HStack(alignment: .bottom, spacing: 4) {
                                Rectangle().fill(.cyan).frame(height:max(2,(c.finalDB+60)/78*g.size.height))
                                Rectangle().fill(.orange).frame(height:max(2,c.finalMS/delayScale*g.size.height))
                            }.frame(height:g.size.height,alignment:.bottom)
                        }
                        Text("\(i+1)").font(.caption2)
                    }
                }
                Text(String(format: "Gain −60…+18 dB\nDelay 0…%.1f ms", delayScale)).font(.caption2).foregroundStyle(.secondary).frame(width: 110)
            }
        }.padding(10).background(.primary.opacity(0.03),in:RoundedRectangle(cornerRadius:8))
    }
}
