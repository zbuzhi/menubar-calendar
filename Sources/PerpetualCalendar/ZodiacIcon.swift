import SwiftUI

// Actual pictograms drawn as paths; no astrological Unicode glyphs or emoji.
struct ZodiacIcon: View {
    let index: Int
    var body: some View {
        Canvas { context, size in
            let sx = size.width / 24, sy = size.height / 24
            var p = Path()
            func line(_ points: [(Double,Double)]) {
                guard let first = points.first else { return }
                p.move(to:CGPoint(x:first.0 * sx,y:first.1 * sy))
                for point in points.dropFirst() { p.addLine(to:CGPoint(x:point.0*sx,y:point.1*sy)) }
            }
            func ellipse(_ x:Double,_ y:Double,_ w:Double,_ h:Double) { p.addEllipse(in:CGRect(x:x*sx,y:y*sy,width:w*sx,height:h*sy)) }
            switch index {
            case 9: // Balance scales
                line([(12,2),(12,21),(6,21),(18,21)]); line([(3,7),(21,7)])
                line([(5,7),(2,15),(8,15),(5,7)]); line([(19,7),(16,15),(22,15),(19,7)])
                ellipse(10,3,4,4)
            case 10: // Scorpion, pincers, feet and a curling tail
                ellipse(8,9,8,10)
                line([(9,11),(5,7),(2,8),(2,4),(5,5),(5,7)])
                line([(15,11),(18,7),(22,8),(22,4),(19,5),(18,7)])
                for y in [12.0,15,18] { line([(9,y),(4,y+2)]); line([(15,y),(20,y+2)]) }
                p.move(to:CGPoint(x:12*sx,y:19*sy)); p.addCurve(to:CGPoint(x:19*sx,y:2*sy),control1:CGPoint(x:23*sx,y:25*sy),control2:CGPoint(x:25*sx,y:3*sy))
                line([(19,2),(17,5),(21,4)])
            case 0: // Goat
                ellipse(7,8,10,13); line([(8,11),(3,5),(4,2),(8,4),(10,8)]); line([(16,11),(21,5),(20,2),(16,4),(14,8)]); line([(9,20),(12,23),(15,20)])
            case 1: // Water bearer: tilted vessel and flowing water
                line([(5,3),(15,3),(18,11),(12,16),(6,12),(5,3)]); line([(15,5),(21,5),(21,10),(18,11)])
                line([(4,16),(7,18),(4,20),(7,22)]); line([(10,17),(13,19),(10,21),(13,23)])
            case 2: // Two fish
                ellipse(2,3,14,7); line([(16,6),(21,2),(21,11),(16,6)]); ellipse(8,14,14,7); line([(8,17),(3,13),(3,22),(8,17)])
            case 3: // Ram
                ellipse(7,8,10,13); ellipse(1,2,9,10); ellipse(14,2,9,10); line([(9,19),(12,23),(15,19)])
            case 4: // Bull
                ellipse(5,8,14,14); line([(6,12),(2,7),(2,2),(8,8)]); line([(18,12),(22,7),(22,2),(16,8)]); ellipse(8,15,8,5)
            case 5: // Twins
                ellipse(3,2,7,7); ellipse(14,2,7,7); line([(1,22),(2,13),(6,10),(11,14),(13,10),(18,10),(22,13),(23,22)]); line([(7,15),(7,23)]); line([(17,15),(17,23)])
            case 6: // Crab
                ellipse(6,8,12,12); ellipse(1,1,6,7); ellipse(17,1,6,7); line([(4,8),(7,12)]); line([(20,8),(17,12)])
                for y in [12.0,16,19] { line([(7,y),(1,y+3)]); line([(17,y),(23,y+3)]) }
            case 7: // Lion
                ellipse(2,2,20,20); ellipse(6,6,12,14); line([(8,10),(9,11)]); line([(15,10),(16,11)]); line([(10,15),(12,17),(14,15)]); line([(12,17),(12,20)])
            case 8: // Maiden
                ellipse(8,1,8,8); line([(7,8),(3,13),(4,22),(20,22),(21,13),(17,8)]); line([(9,10),(9,18),(15,18),(15,10)]); line([(2,5),(2,16),(6,12)])
            default: // Archer bow and arrow
                p.move(to:CGPoint(x:3*sx,y:3*sy)); p.addQuadCurve(to:CGPoint(x:3*sx,y:21*sy),control:CGPoint(x:23*sx,y:12*sy))
                line([(3,3),(7,12),(3,21)]); line([(1,12),(23,12),(19,8)]); line([(23,12),(19,16)])
            }
            context.stroke(p,with:.foreground,style:StrokeStyle(lineWidth:max(0.65,size.width / 15),lineCap:.round,lineJoin:.round))
        }
        .accessibilityHidden(true)
    }
}
struct MoonDisc: View {
    let fraction: Double
    var body: some View {
        Canvas { c,size in
            let r = min(size.width,size.height)/2
            let center = CGPoint(x:size.width/2,y:size.height/2)
            c.fill(Path(ellipseIn:CGRect(x:center.x-r,y:center.y-r,width:r*2,height:r*2)),with:.color(.primary.opacity(0.13)))
            var lit = Path()
            let waxing = fraction < 0.5
            let phase = cos(2 * .pi * fraction)
            for step in 0...100 {
                let y = -r + Double(step) * 2*r/100
                let edge = sqrt(max(0,r*r-y*y))
                let outer = waxing ? edge : -edge
                let inner = (waxing ? 1.0 : -1.0) * phase * edge
                lit.addRect(CGRect(x:center.x+min(inner,outer),y:center.y+y,width:max(0.1,abs(outer-inner)),height:max(0.5,r/45)))
            }
            c.fill(lit,with:.color(.primary.opacity(0.75)))
        }.accessibilityLabel("月相示意")
    }
}
