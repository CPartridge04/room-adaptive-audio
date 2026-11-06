import Foundation

// Free-field, regularized inverse of the four speaker-to-ear paths.
// This is a geometric approximation, not a measured head/room transfer function.
private struct Complex {
    var r: Double = 0; var i: Double = 0
    var conjugate: Complex { Complex(r: r, i: -i) }
    var power: Double { r*r+i*i }
    static func + (a: Self,b: Self) -> Self { Self(r:a.r+b.r,i:a.i+b.i) }
    static func - (a: Self,b: Self) -> Self { Self(r:a.r-b.r,i:a.i-b.i) }
    static func * (a: Self,b: Self) -> Self { Self(r:a.r*b.r-a.i*b.i,i:a.r*b.i+a.i*b.r) }
    static func / (a: Self,b: Double) -> Self { Self(r:a.r/b,i:a.i/b) }
}
struct EarFilters {
    static let size = 512
    static let latency = 256.0 / 48000
    var taps: [[Double]]
    var gain: [Double]
    var delay: [Double]
    init(room: Room) {
        let c = room.calculations(2)
        let near = c.map { min($0.leftEar,$0.rightEar) }
        gain = near.map { $0/2 }
        delay = near.map { ((near.max() ?? 0)-$0)/343 }
        var spectra = Array(repeating:Array(repeating:Complex(),count:Self.size),count:4)
        for k in 0...Self.size/2 {
            let omega = 2 * Double.pi * Double(k)*48000/Double(Self.size)
            func path(_ ear: Double,_ speaker: Int) -> Complex {
                let phase = -omega*(ear-near[speaker])/343
                return Complex(r:cos(phase)*near[speaker]/ear,i:sin(phase)*near[speaker]/ear)
            }
            let a = path(c[0].leftEar,0), b = path(c[1].leftEar,1)
            let c0 = path(c[0].rightEar,0), d = path(c[1].rightEar,1)
            // (H* H + lambda I)^-1 H*. Regularization bounds amplification
            // when the ears see nearly identical paths (especially sideways).
            let u = a.power+c0.power+0.04, v = b.power+d.power+0.04
            let z = a.conjugate*b+c0.conjugate*d
            let determinant = max(1e-12,u*v-z.power)
            let uc = Complex(r:u), vc = Complex(r:v)
            let values = [(vc*a.conjugate-z*b.conjugate)/determinant,
                          (vc*c0.conjugate-z*d.conjugate)/determinant,
                          (uc*b.conjugate-z.conjugate*a.conjugate)/determinant,
                          (uc*d.conjugate-z.conjugate*c0.conjugate)/determinant]
            // Half a filter of latency makes the inverse approximately causal.
            for j in 0..<4 {
                var value = values[j]*Complex(r:k % 2 == 0 ? 1 : -1)
                if k == 0 || k == Self.size/2 { value.i = 0 }
                spectra[j][k] = value
                if k > 0 && k < Self.size/2 { spectra[j][Self.size-k] = value.conjugate }
            }
        }
        taps = spectra.map { spectrum in
            var x = spectrum
            var j = 0
            for i in 1..<Self.size {
                var bit = Self.size >> 1
                while j & bit != 0 { j ^= bit; bit >>= 1 }
                j ^= bit
                if i < j { x.swapAt(i,j) }
            }
            var length = 2
            while length <= Self.size {
                let step = Complex(r:cos(2 * .pi/Double(length)),i:sin(2 * .pi/Double(length)))
                for start in stride(from:0,to:Self.size,by:length) {
                    var w = Complex(r:1)
                    for offset in 0..<length/2 {
                        let a = x[start+offset], b = x[start+offset+length/2]*w
                        x[start+offset] = a+b; x[start+offset+length/2] = a-b; w = w*step
                    }
                }
                length *= 2
            }
            return x.enumerated().map { index,value in
                value.r/Double(Self.size) * (0.5-0.5*cos(2 * .pi*Double(index)/Double(Self.size)))
            }
        }
    }
}
