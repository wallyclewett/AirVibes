import CoreLocation
import Foundation

final class LocationProvider: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    var onUpdate: ((CLLocation?) -> Void)?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func request() {
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .denied, .restricted: onUpdate?(nil)
        default: manager.requestLocation()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .notDetermined: break
        case .denied, .restricted: onUpdate?(nil)
        default: manager.requestLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        onUpdate?(locations.last)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        onUpdate?(nil)
    }
}

@MainActor
final class AppModel: ObservableObject {
    private let defaults = UserDefaults.standard

    // Settings (saved)
    @Published var units: Units { didSet { defaults.set(units.rawValue, forKey: "units") } }
    @Published var sport: Sport { didSet { defaults.set(sport.rawValue, forKey: "sport") } }
    @Published var minWind: Double { didSet { defaults.set(minWind, forKey: "minWind") } }
    @Published var maxGust: Double { didSet { defaults.set(maxGust, forKey: "maxGust") } }
    /// A spot you picked. nil means "nearest beach to me".
    @Published var pinned: Spot? = nil { didSet { savePinned() } }

    // Live data
    @Published private(set) var spot: Spot? = nil
    @Published private(set) var forecast: Forecast? = nil
    @Published private(set) var station: Station? = nil
    @Published private(set) var tide: TideState? = nil
    @Published private(set) var nearby: [BeachWind] = []
    @Published private(set) var status = "Finding your location…"
    @Published private(set) var updated: Date? = nil
    @Published private(set) var loading = false

    private var location: CLLocation?
    private var beachCache: [Beach]?
    private let locator = LocationProvider()
    private var timer: Timer?

    var limits: Limits { Limits(min: minWind, maxGust: maxGust) }

    init() {
        units = Units(rawValue: defaults.string(forKey: "units") ?? "") ?? .kn
        sport = Sport(rawValue: defaults.string(forKey: "sport") ?? "") ?? .kite
        minWind = defaults.object(forKey: "minWind") as? Double ?? 12
        maxGust = defaults.object(forKey: "maxGust") as? Double ?? 30
        if let data = defaults.data(forKey: "pinned") { pinned = try? JSONDecoder().decode(Spot.self, from: data) }

        locator.onUpdate = { [weak self] loc in
            Task { @MainActor in
                guard let self else { return }
                if let loc { self.location = loc }
                await self.refresh()
            }
        }
        locator.request()
        timer = Timer.scheduledTimer(withTimeInterval: 10 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.locator.request()
            }
        }
    }

    private func savePinned() {
        if let pinned, let data = try? JSONEncoder().encode(pinned) { defaults.set(data, forKey: "pinned") }
        else { defaults.removeObject(forKey: "pinned") }
    }

    func applySport(_ s: Sport) {
        sport = s
        if let p = s.preset { minWind = p.min; maxGust = p.maxGust }
    }

    func pin(_ s: Spot?) {
        pinned = s
        Task { await refresh() }
    }

    func rating(speed: Double, gust: Double, deg: Double, sectors: [Int] = []) -> (level: Level, why: String) {
        rate(speed: speed, gust: gust, deg: deg, sectors: sectors, limits: limits, units: units)
    }

    var currentRating: (level: Level, why: String)? {
        guard let f = forecast else { return nil }
        return rating(speed: f.speed, gust: f.gust, deg: f.deg, sectors: spot?.sectors ?? [])
    }

    var windows: [RideWindow] {
        guard let f = forecast else { return [] }
        return rideWindows(f.hours, tz: f.timeZone, sectors: spot?.sectors ?? [], limits: limits, units: units)
    }

    func refresh() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        do {
            if beachCache == nil { beachCache = try await WeatherAPI.beaches() }
            let centre: (lat: Double, lon: Double)?
            if let loc = location { centre = (loc.coordinate.latitude, loc.coordinate.longitude) }
            else if let p = pinned { centre = (p.lat, p.lon) }
            else { centre = nil }
            guard let c = centre else {
                status = "Location is off. Search for a spot below, or allow AirVibes in System Settings → Privacy & Security → Location Services."
                return
            }
            let near = pickBeaches(beachCache ?? [], lat: c.lat, lon: c.lon, radiusKm: 30, max: 8)
            guard let s = pinned ?? near.first?.spot else {
                status = "No named beaches within 30 km. Search for a spot below."
                return
            }
            spot = s

            async let f = WeatherAPI.forecast(lat: s.lat, lon: s.lon)
            async let winds = WeatherAPI.currentWind(near)
            async let obs = WeatherAPI.stations()
            async let t = WeatherAPI.tide(lat: s.lat, lon: s.lon)

            forecast = try await f
            nearby = ((try? await winds) ?? []).sorted {
                let a = rating(speed: $0.speed, gust: $0.gust, deg: $0.deg).level.rank
                let b = rating(speed: $1.speed, gust: $1.gust, deg: $1.deg).level.rank
                return a != b ? a < b : $0.speed > $1.speed
            }
            let stations = (try? await obs) ?? []
            station = stations
                .map { st -> Station in var st = st; st.dist = distanceKm(s.lat, s.lon, st.lat, st.lon); return st }
                .filter { $0.dist <= 20 }
                .min { $0.dist < $1.dist }
            tide = await t
            updated = Date()
            status = ""
        } catch {
            status = "Couldn't update: \(error.localizedDescription)"
        }
    }

    /// Menu bar text, e.g. "↘ 14 kn".
    var menuTitle: String {
        guard let f = forecast else { return "AirVibes" }
        return "\(arrowChar(f.deg)) \(units.fmt(f.speed)) \(units.label)"
    }
}
