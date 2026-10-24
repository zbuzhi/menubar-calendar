import SwiftUI
import CalendarCore

/// Vector glass vessel with sand volumes tied to elapsed time; no icon font or timer animation.
struct NoteHourglass: View {
    let progress: Double?
    var body: some View {
        Canvas { context, size in
            let p = min(1,max(0,progress ?? 0))
            let rgb = NoteProgressTint.rgb(p)
            let sand = Color(.sRGB,red:rgb.red,green:rgb.green,blue:rgb.blue,opacity:0.62)
            let w = size.width, h = size.height
            var vessel = Path()
            vessel.move(to:CGPoint(x:w * 0.2,y:2))
            vessel.addCurve(to:CGPoint(x:w * 0.44,y:h * 0.5),control1:CGPoint(x:w * 0.2,y:h * 0.34),control2:CGPoint(x:w * 0.42,y:h * 0.4))
            vessel.addCurve(to:CGPoint(x:w * 0.2,y:h - 2),control1:CGPoint(x:w * 0.42,y:h * 0.6),control2:CGPoint(x:w * 0.2,y:h * 0.66))
            vessel.addLine(to:CGPoint(x:w * 0.8,y:h - 2))
            vessel.addCurve(to:CGPoint(x:w * 0.56,y:h * 0.5),control1:CGPoint(x:w * 0.8,y:h * 0.66),control2:CGPoint(x:w * 0.58,y:h * 0.6))
            vessel.addCurve(to:CGPoint(x:w * 0.8,y:2),control1:CGPoint(x:w * 0.58,y:h * 0.4),control2:CGPoint(x:w * 0.8,y:h * 0.34))
            vessel.closeSubpath()
            context.fill(vessel,with:.linearGradient(Gradient(colors:[.white.opacity(0.35),sand.opacity(0.08),.white.opacity(0.12)]),startPoint:.zero,endPoint:CGPoint(x:w,y:h)))
            var inside = context; inside.clip(to:vessel)
            let top = 3 + (h * 0.42 - 3) * p
            inside.fill(Path(CGRect(x:0,y:top,width:w,height:max(0,h * 0.46 - top))),with:.color(sand.opacity(0.65)))
            let pileHeight = (h * 0.36) * sqrt(p)
            var pile = Path()
            pile.move(to:CGPoint(x:w * 0.12,y:h - 2))
            pile.addQuadCurve(to:CGPoint(x:w * 0.5,y:h - 2 - pileHeight),control:CGPoint(x:w * 0.32,y:h - 3 - pileHeight * 0.6))
            pile.addQuadCurve(to:CGPoint(x:w * 0.88,y:h - 2),control:CGPoint(x:w * 0.68,y:h - 3 - pileHeight * 0.6))
            pile.closeSubpath(); inside.fill(pile,with:.color(sand))
            if p > 0 && p < 1 {
                inside.fill(Path(CGRect(x:w / 2 - 0.35,y:h * 0.47,width:0.7,height:h * 0.48 - pileHeight)),with:.color(sand.opacity(0.65)))
            }
            context.stroke(vessel,with:.color(.secondary.opacity(0.35)),lineWidth:0.75)
            for y in [CGFloat(1),h - 1] {
                let cap = Path(roundedRect:CGRect(x:w * 0.1,y:y - 0.7,width:w * 0.8,height:1.4),cornerRadius:0.7)
                context.fill(cap,with:.color(.secondary.opacity(0.5)))
            }
        }.frame(width:14,height:18).accessibilityHidden(true)
    }
}
