import Foundation

enum Level: String {
    case go, maybe, nogo

    var label: String {
        switch self {
        case .go: return "Go"
        case .maybe: return "Marginal"
        case .nogo: return "No go"
        }
    }

    var rank: Int {
        switch self {
        case .go: return 0
        case .maybe: return 1
        case .nogo: return 2
        }
    }
}

enum Units: String, CaseIterable, Identifiable {
    case kn, kmh, ms

    var id: String { rawValue }

    var label: String {
        switch self {
        case .kn: return "kn"
        case .kmh: return "km/h"
        case .ms: return "m/s"
        }
    }

    private var factor: Double {
        switch self {
        case .kn: return 1
        case .kmh: return 1.852
        case .ms: return 0.514444
        }
    }

    /// Formats a speed given in knots.
    func fmt(_ kn: Double) -> String { String(Int((kn * factor).rounded())) }
}

enum Sport: String, CaseIterable, Identifiable {
    case kite, wing, windsurf, sail, custom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .kite: return "Kitesurf"
        case .wing: return "Wing foil"
        case .windsurf: return "Windsurf"
        case .sail: return "Dinghy sailing"
        case .custom: return "Custom"
        }
    }

    /// Minimum wind and maximum gust in knots.
    var preset: (min: Double, maxGust: Double)? {
        switch self {
        case .kite: return (12, 30)
        case .wing: return (12, 28)
        case .windsurf: return (15, 35)
        case .sail: return (6, 20)
        case .custom: return nil
        }
    }
}

struct Spot: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var lat: Double
    var lon: Double
    var sectors: [Int] = []
}

struct Beach: Hashable, Identifiable {
    let id: String
    let name: String
    let lat: Double
    let lon: Double
    var dist: Double = 0

    var spot: Spot { Spot(id: id, name: name, lat: lat, lon: lon) }
}

struct Limits {
    var min: Double
    var maxGust: Double
}

let compass16 = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE", "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]

func sectorOf(_ deg: Double) -> Int { Int((deg / 22.5).rounded()) % 16 }
func dirName(_ deg: Double) -> String { compass16[sectorOf(deg)] }

/// Arrow pointing where the wind blows to, for a wind blowing from `deg`.
func arrowChar(_ deg: Double) -> String {
    let arrows = ["↓", "↙", "←", "↖", "↑", "↗", "→", "↘"]
    return arrows[Int((deg / 45).rounded()) % 8]
}

func rate(speed: Double, gust: Double, deg: Double, sectors: [Int], limits: Limits, units: Units) -> (level: Level, why: String) {
    let u = units.label
    let dirOk = sectors.isEmpty || sectors.contains(sectorOf(deg))
    if gust > limits.maxGust {
        return (.nogo, "Gusts \(units.fmt(gust)) \(u) are over your \(units.fmt(limits.maxGust)) limit.")
    }
    if !dirOk {
        return (.nogo, "Wind from \(dirName(deg)) isn't one of your directions here.")
    }
    if speed >= limits.min {
        if gust - speed > 12 {
            return (.maybe, "Enough wind, but gusty: \(units.fmt(speed)) gusting \(units.fmt(gust)).")
        }
        return (.go, "\(units.fmt(speed)) \(u) from \(dirName(deg)), gusts to \(units.fmt(gust)).")
    }
    if speed >= limits.min - 2 {
        return (.maybe, "Just under your minimum: \(units.fmt(speed)) of \(units.fmt(limits.min)) needed.")
    }
    return (.nogo, "Too light: \(units.fmt(speed)) \(u), you need \(units.fmt(limits.min)).")
}

func distanceKm(_ aLat: Double, _ aLon: Double, _ bLat: Double, _ bLon: Double) -> Double {
    let r = Double.pi / 180
    let dLat = (bLat - aLat) * r, dLon = (bLon - aLon) * r
    let h = pow(sin(dLat / 2), 2) + cos(aLat * r) * cos(bLat * r) * pow(sin(dLon / 2), 2)
    return 12742 * asin(sqrt(h))
}

/// Nearest copy of each beach name, then the closest beaches at least `gapKm` apart.
func pickBeaches(_ all: [Beach], lat: Double, lon: Double, radiusKm: Double, max: Int, gapKm: Double = 2.5) -> [Beach] {
    var byName: [String: Beach] = [:]
    for var b in all {
        b.dist = distanceKm(lat, lon, b.lat, b.lon)
        guard b.dist <= radiusKm else { continue }
        if let prev = byName[b.name], prev.dist <= b.dist { continue }
        byName[b.name] = b
    }
    var out: [Beach] = []
    for b in byName.values.sorted(by: { $0.dist < $1.dist }) {
        if out.count >= max { break }
        if out.allSatisfy({ distanceKm($0.lat, $0.lon, b.lat, b.lon) >= gapKm }) { out.append(b) }
    }
    return out
}

// MARK: - Weather data

struct Hour: Identifiable {
    let time: Date
    let speed: Double
    let gust: Double
    let deg: Double
    var id: Date { time }
}

struct Forecast {
    let speed: Double
    let gust: Double
    let deg: Double
    let hours: [Hour]      // from the current hour onwards
    let timeZone: TimeZone
}

struct BeachWind: Identifiable {
    let beach: Beach
    let speed: Double
    let gust: Double
    let deg: Double
    var id: String { beach.id }
}

struct Station {
    let name: String
    let lat: Double
    let lon: Double
    let time: Date
    let speed: Double
    let gust: Double?
    let deg: Double?
    var dist: Double = 0
}

struct TideEvent {
    let isHigh: Bool
    let time: Date
    let height: Double
}

struct TideState {
    let rising: Bool
    let fill: Double   // 0 = low, 1 = high
    let next: TideEvent
    let after: TideEvent?
}

struct RideWindow: Identifiable {
    let start: Date
    let end: Date
    let minSpeed: Double
    let maxSpeed: Double
    let deg: Double
    var id: Date { start }
}

/// Daylight (6am–6pm) stretches of 2+ hours rated Go.
func rideWindows(_ hours: [Hour], tz: TimeZone, sectors: [Int], limits: Limits, units: Units) -> [RideWindow] {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = tz
    var out: [RideWindow] = []
    var run: [Hour] = []
    func flush() {
        if run.count >= 2, let first = run.first, let last = run.last {
            let speeds = run.map(\.speed)
            out.append(RideWindow(start: first.time, end: last.time.addingTimeInterval(3600),
                                  minSpeed: speeds.min()!, maxSpeed: speeds.max()!, deg: run[run.count / 2].deg))
        }
        run = []
    }
    for h in hours {
        let hr = cal.component(.hour, from: h.time)
        let ok = hr >= 6 && hr <= 18 && rate(speed: h.speed, gust: h.gust, deg: h.deg, sectors: sectors, limits: limits, units: units).level == .go
        if ok { run.append(h) } else { flush() }
    }
    flush()
    return out
}

/// Finds highs and lows in an hourly sea level series and where "now" sits between them.
func tideState(times: [Date], levels: [Double?], now: Date = Date()) -> TideState? {
    var events: [TideEvent] = []
    if levels.count >= 3 {
        for i in 1..<(levels.count - 1) {
            guard let a = levels[i - 1], let b = levels[i], let c = levels[i + 1] else { continue }
            let high = b > a && b >= c, low = b < a && b <= c
            guard high || low else { continue }
            let den = a - 2 * b + c
            let k = den != 0 ? 0.5 * (a - c) / den : 0   // vertex of the parabola through the 3 points
            events.append(TideEvent(isHigh: high, time: times[i].addingTimeInterval(k * 3600), height: b - 0.25 * (a - c) * k))
        }
    }
    guard let ni = events.firstIndex(where: { $0.time > now }), ni >= 1 else { return nil }
    let prev = events[ni - 1], next = events[ni]
    let f = min(1, max(0, now.timeIntervalSince(prev.time) / next.time.timeIntervalSince(prev.time)))
    let level = prev.height + (next.height - prev.height) * (1 - cos(f * .pi)) / 2
    let lo = min(prev.height, next.height), hi = max(prev.height, next.height)
    return TideState(rising: next.isHigh, fill: hi > lo ? (level - lo) / (hi - lo) : 0.5,
                     next: next, after: ni + 1 < events.count ? events[ni + 1] : nil)
}
