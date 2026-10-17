import Foundation

/// Same free, keyless sources as the web app.
enum WeatherAPI {
    static let beachesURL = URL(string: "https://wallyclewett.github.io/airvibes/beaches.json")!
    static let stationsURL = URL(string: "https://raw.githubusercontent.com/wallyclewett/airvibes/data/obs.json")!

    struct APIError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    private static func get(_ url: URL) async throws -> Data {
        var req = URLRequest(url: url)
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.timeoutInterval = 20
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw APIError(message: "\(url.host ?? "server") returned \(http.statusCode)")
        }
        return data
    }

    /// Open-Meteo returns one object for one location and an array for several.
    private static func decodeOneOrMany<T: Decodable>(_ type: T.Type, _ data: Data) throws -> [T] {
        if let many = try? JSONDecoder().decode([T].self, from: data) { return many }
        return [try JSONDecoder().decode(T.self, from: data)]
    }

    private static func localTimes(_ strings: [String], offset: Int) -> [Date] {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: offset)
        f.dateFormat = "yyyy-MM-dd'T'HH:mm"
        return strings.map { f.date(from: $0) ?? .distantPast }
    }

    // MARK: Beaches

    static func beaches() async throws -> [Beach] {
        let data = try await get(beachesURL)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rows = root["beaches"] as? [[Any]] else { throw APIError(message: "Beach list is unreadable") }
        return rows.compactMap { row in
            guard row.count >= 3, let name = row[0] as? String,
                  let lat = (row[1] as? NSNumber)?.doubleValue, let lon = (row[2] as? NSNumber)?.doubleValue else { return nil }
            return Beach(id: "b:\(name)@\(lat),\(lon)", name: name, lat: lat, lon: lon)
        }
    }

    // MARK: Forecast

    private struct OMForecast: Decodable {
        struct Current: Decodable {
            let wind_speed_10m: Double
            let wind_direction_10m: Double
            let wind_gusts_10m: Double
        }
        struct Hourly: Decodable {
            let time: [String]
            let wind_speed_10m: [Double?]
            let wind_direction_10m: [Double?]
            let wind_gusts_10m: [Double?]
        }
        let utc_offset_seconds: Int
        let current: Current
        let hourly: Hourly?
    }

    private static func forecastURL(lats: [Double], lons: [Double], hourly: Bool) -> URL {
        var c = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        var q = [
            URLQueryItem(name: "latitude", value: lats.map { String($0) }.joined(separator: ",")),
            URLQueryItem(name: "longitude", value: lons.map { String($0) }.joined(separator: ",")),
            URLQueryItem(name: "current", value: "wind_speed_10m,wind_direction_10m,wind_gusts_10m"),
            URLQueryItem(name: "wind_speed_unit", value: "kn"),
            URLQueryItem(name: "timezone", value: "auto"),
        ]
        if hourly {
            q.append(URLQueryItem(name: "hourly", value: "wind_speed_10m,wind_direction_10m,wind_gusts_10m"))
            q.append(URLQueryItem(name: "forecast_days", value: "3"))
        }
        c.queryItems = q
        return c.url!
    }

    static func forecast(lat: Double, lon: Double) async throws -> Forecast {
        let data = try await get(forecastURL(lats: [lat], lons: [lon], hourly: true))
        guard let f = try decodeOneOrMany(OMForecast.self, data).first, let h = f.hourly else {
            throw APIError(message: "Forecast is unreadable")
        }
        let times = localTimes(h.time, offset: f.utc_offset_seconds)
        let hourStart = Date().addingTimeInterval(-3600)
        var hours: [Hour] = []
        for i in times.indices where times[i] > hourStart {
            guard let s = h.wind_speed_10m[i], let g = h.wind_gusts_10m[i], let d = h.wind_direction_10m[i] else { continue }
            hours.append(Hour(time: times[i], speed: s, gust: g, deg: d))
        }
        return Forecast(speed: f.current.wind_speed_10m, gust: f.current.wind_gusts_10m, deg: f.current.wind_direction_10m,
                        hours: hours, timeZone: TimeZone(secondsFromGMT: f.utc_offset_seconds) ?? .current)
    }

    /// Current forecast wind for several beaches in one request.
    static func currentWind(_ beaches: [Beach]) async throws -> [BeachWind] {
        guard !beaches.isEmpty else { return [] }
        let data = try await get(forecastURL(lats: beaches.map(\.lat), lons: beaches.map(\.lon), hourly: false))
        let all = try decodeOneOrMany(OMForecast.self, data)
        return zip(beaches, all).map { b, f in
            BeachWind(beach: b, speed: f.current.wind_speed_10m, gust: f.current.wind_gusts_10m, deg: f.current.wind_direction_10m)
        }
    }

    // MARK: Measured wind

    private struct ObsFile: Decodable {
        struct S: Decodable {
            let name: String
            let lat: Double
            let lon: Double
            let t: String
            let spd: Double
            let gust: Double?
            let deg: Double?
        }
        let stations: [S]
    }

    static func stations() async throws -> [Station] {
        let file = try JSONDecoder().decode(ObsFile.self, from: try await get(stationsURL))
        let iso = ISO8601DateFormatter()
        let isoFrac = ISO8601DateFormatter()
        isoFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let cutoff = Date().addingTimeInterval(-2 * 3600)
        return file.stations.compactMap { s in
            guard let t = iso.date(from: s.t) ?? isoFrac.date(from: s.t), t > cutoff else { return nil }
            return Station(name: s.name, lat: s.lat, lon: s.lon, time: t, speed: s.spd, gust: s.gust, deg: s.deg)
        }
    }

    // MARK: Tide

    private struct OMMarine: Decodable {
        struct Hourly: Decodable {
            let time: [String]
            let sea_level_height_msl: [Double?]
        }
        let utc_offset_seconds: Int
        let hourly: Hourly?
    }

    /// Modelled tide. Beach points often fall on a land cell, so also try points nudged ~5 km each way.
    static func tide(lat: Double, lon: Double) async -> TideState? {
        let d = 0.05
        let pts = [(0.0, 0.0), (0, d), (d, 0), (-d, 0), (0, -d)].map { (lat + $0.0, lon + $0.1) }
        var c = URLComponents(string: "https://marine-api.open-meteo.com/v1/marine")!
        c.queryItems = [
            URLQueryItem(name: "latitude", value: pts.map { String(format: "%.4f", $0.0) }.joined(separator: ",")),
            URLQueryItem(name: "longitude", value: pts.map { String(format: "%.4f", $0.1) }.joined(separator: ",")),
            URLQueryItem(name: "hourly", value: "sea_level_height_msl"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "past_days", value: "1"),
            URLQueryItem(name: "forecast_days", value: "2"),
        ]
        guard let data = try? await get(c.url!), let all = try? decodeOneOrMany(OMMarine.self, data) else { return nil }
        guard let hit = all.first(where: { ($0.hourly?.sea_level_height_msl.compactMap { $0 }.count ?? 0) > 24 }),
              let h = hit.hourly else { return nil }
        return tideState(times: localTimes(h.time, offset: hit.utc_offset_seconds), levels: h.sea_level_height_msl)
    }

    // MARK: Place search

    struct Place: Decodable, Identifiable {
        let id: Int
        let name: String
        let latitude: Double
        let longitude: Double
        let admin1: String?
        let country_code: String?
    }

    static func searchPlaces(_ query: String) async throws -> [Place] {
        var c = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        c.queryItems = [
            URLQueryItem(name: "name", value: query),
            URLQueryItem(name: "count", value: "6"),
            URLQueryItem(name: "language", value: "en"),
            URLQueryItem(name: "format", value: "json"),
        ]
        struct Result: Decodable { let results: [Place]? }
        return try JSONDecoder().decode(Result.self, from: try await get(c.url!)).results ?? []
    }
}
