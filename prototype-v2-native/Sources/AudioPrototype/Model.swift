import Foundation

struct Speaker: Identifiable {
    let id: Int
    var x: Double; var y: Double; var z: Double = 1.2
    var trim: Double = 0; var delayTrim: Double = 0
    var mute = false; var solo = false
    var name: String { ["Front left", "Front right", "Rear left", "Rear right"][id] }
}
struct Calculation {
    var distance: Double; var leftEar: Double; var rightEar: Double
    var automaticDB: Double; var automaticMS: Double
    var finalDB: Double; var finalMS: Double
}
struct Room {
    var width = 4.0; var length = 5.0
    var x = 2.0; var y = 3.0; var height = 1.2
    var measuredCalibration = false
    var measuredGain = [0.0, 0.0]
    var measuredDelay = [0.0, 0.0]
    var virtualHeadphones = false
    var heading = 0.0; var earSpacing = 0.18
    var count = 2
    var volume = true; var alignment = true; var rotation = true; var separation = false
    var speakers = [Speaker(id: 0, x: 0.4, y: 0.4), Speaker(id: 1, x: 3.6, y: 0.4), Speaker(id: 2, x: 0.4, y: 4.6), Speaker(id: 3, x: 3.6, y: 4.6)]
    var ears: [(Double, Double)] {
        let a = heading * .pi / 180, dx = cos(a) * earSpacing / 2, dy = sin(a) * earSpacing / 2
        return [(x-dx,y-dy),(x+dx,y+dy)]
    }
    func distance(_ s: Speaker, _ px: Double, _ py: Double) -> Double {
        max(0.1, sqrt(pow(s.x-px,2) + pow(s.y-py,2) + pow(s.z-height,2)))
    }
    func calculations(_ n: Int? = nil) -> [Calculation] {
        let active = Array(speakers.prefix(n ?? count))
        let distances = active.map { distance($0,x,y) }
        let longest = distances.max() ?? 0
        let longestNearEar = active.map { min(distance($0,ears[0].0,ears[0].1),distance($0,ears[1].0,ears[1].1)) }.max() ?? 0
        return zip(active, distances).map { s,d in
            let nearEar = min(distance(s,ears[0].0,ears[0].1),distance(s,ears[1].0,ears[1].1))
            let db = measuredCalibration && s.id < 2 ? measuredGain[s.id] : virtualHeadphones ? 20*log10(nearEar/2) : volume ? 20 * log10(d / 2) : 0 // fixed 2 m reference
            let ms = measuredCalibration && s.id < 2 ? measuredDelay[s.id] : virtualHeadphones ? (longestNearEar-nearEar)/343*1000 : alignment ? (longest-d) / 343 * 1000 : 0
            return Calculation(distance: d, leftEar: distance(s,ears[0].0,ears[0].1), rightEar: distance(s,ears[1].0,ears[1].1), automaticDB: db, automaticMS: ms, finalDB: min(18,max(-60,db+s.trim)), finalMS: min(200,max(0,ms+s.delayTrim)))
        }
    }
    mutating func constrain() {
        width = finiteClamp(width, 1, 30); length = finiteClamp(length, 1, 30)
        x = finiteClamp(x,0,width); y = finiteClamp(y,0,length)
        height = finiteClamp(height,0,3); earSpacing = finiteClamp(earSpacing,0.1,0.3)
        heading = finiteClamp(heading,0,360)
        for i in speakers.indices {
            speakers[i].x = finiteClamp(speakers[i].x,0,width); speakers[i].y = finiteClamp(speakers[i].y,0,length)
            speakers[i].z = finiteClamp(speakers[i].z,0,5)
            speakers[i].trim = finiteClamp(speakers[i].trim,-24,12)
            speakers[i].delayTrim = finiteClamp(speakers[i].delayTrim,0,100)
        }
    }
}
func finiteClamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double { v.isFinite ? min(hi,max(lo,v)) : lo }
struct DSPSettings {
    var gain = [1.0,1.0]; var delay = [0.0,0.0]
    var left = [1.0,0.0]; var right = [0.0,1.0]
    var cancel = [0.0,0.0]; var crossDelay = [0.0,0.0]
    var earFilters: EarFilters?
    var processed = true; var master = 0.15; var repeating = false
    init(room: Room = Room()) {
        earFilters = room.virtualHeadphones ? EarFilters(room: room) : nil
        let c = room.calculations(2)
        let solo = room.speakers.prefix(2).contains { $0.solo }
        for i in 0..<2 {
            let s = room.speakers[i]
            gain[i] = (s.mute || (solo && !s.solo)) ? 0 : pow(10,c[i].finalDB/20)
            delay[i] = c[i].finalMS/1000
            if room.rotation {
                let a = room.heading * .pi / 180
                let lateral = ((s.x-room.x)*cos(a)+(s.y-room.y)*sin(a)) / max(0.1,hypot(s.x-room.x,s.y-room.y))
                left[i] = sqrt((1-lateral)/2); right[i] = sqrt((1+lateral)/2)
            }
            if room.separation {
                cancel[i] = 0.35 * min(c[i].leftEar,c[i].rightEar) / max(c[i].leftEar,c[i].rightEar)
                crossDelay[i] = abs(c[i].leftEar-c[i].rightEar)/343
            }
        }
        if let filters = earFilters {
            for i in 0..<2 {
                let s = room.speakers[i]
                gain[i] = (s.mute || (solo && !s.solo)) ? 0 : min(pow(10,18.0/20),filters.gain[i]*pow(10,s.trim/20))
                delay[i] = min(0.2,filters.delay[i]+s.delayTrim/1000)
            }
        }
        if room.rotation {
            let l = max(0.001,hypot(left[0],left[1])), r = max(0.001,hypot(right[0],right[1]))
            for i in 0..<2 { left[i] /= l; right[i] /= r }
        }
    }
}
