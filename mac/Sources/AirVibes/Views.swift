import AppKit
import SwiftUI

extension Level {
    var color: Color {
        switch self {
        case .go: return .green
        case .maybe: return .orange
        case .nogo: return .red
        }
    }
}

private func clock(_ date: Date, _ tz: TimeZone) -> String {
    let f = DateFormatter()
    f.timeZone = tz
    f.dateFormat = "h:mma"
    f.amSymbol = "am"
    f.pmSymbol = "pm"
    return f.string(from: date)
}

private func dayHour(_ date: Date, _ tz: TimeZone) -> String {
    let f = DateFormatter()
    f.timeZone = tz
    f.dateFormat = "EEE ha"
    f.amSymbol = "am"
    f.pmSymbol = "pm"
    return f.string(from: date)
}

private func ago(_ date: Date) -> String {
    let m = Int(Date().timeIntervalSince(date) / 60)
    if m < 1 { return "just now" }
    if m < 60 { return "\(m) min ago" }
    return "\(m / 60) h \(m % 60) min ago"
}

struct Pill: View {
    let level: Level
    var body: some View {
        Text(level.label.uppercased())
            .font(.system(size: 11, weight: .bold))
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(level.color, in: RoundedRectangle(cornerRadius: 5))
            .foregroundStyle(.white)
    }
}

struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased()).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary).tracking(0.6)
    }
}

/// Water fills the tile to the current tide level; the arrow says which way it's going.
struct TideIcon: View {
    let state: TideState
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7).fill(Color.secondary.opacity(0.12))
            GeometryReader { g in
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    Rectangle().fill(Color.accentColor.opacity(0.75))
                        .frame(height: g.size.height * (0.15 + 0.7 * state.fill))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 7))
            Image(systemName: state.rising ? "arrow.up" : "arrow.down").font(.system(size: 13, weight: .bold))
        }
        .frame(width: 30, height: 30)
    }
}

struct HourStrip: View {
    @EnvironmentObject var model: AppModel
    let hours: [Hour]
    let tz: TimeZone

    var body: some View {
        let top = max(model.maxGust, hours.map(\.gust).max() ?? 1) * 1.05
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(hours) { h in
                    let level = model.rating(speed: h.speed, gust: h.gust, deg: h.deg, sectors: model.spot?.sectors ?? []).level
                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(level == .nogo ? Color.secondary.opacity(0.35) : level.color)
                            .frame(height: 56 * h.speed / top)
                        Rectangle().fill(Color.primary).frame(height: 2)
                            .offset(y: -56 * h.gust / top + 1)
                    }
                    .frame(maxWidth: .infinity, maxHeight: 56, alignment: .bottom)
                    .help("\(dayHour(h.time, tz)): \(model.units.fmt(h.speed)) gusting \(model.units.fmt(h.gust)) from \(dirName(h.deg))")
                }
            }
            .frame(height: 56)
            HStack {
                ForEach(Array(stride(from: 0, to: hours.count, by: 6)), id: \.self) { i in
                    Text(clock(hours[i].time, tz).replacingOccurrences(of: ":00", with: ""))
                        .font(.system(size: 9)).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

struct PopoverView: View {
    @EnvironmentObject var model: AppModel
    @State private var query = ""
    @State private var results: [WeatherAPI.Place] = []
    @State private var searching = false
    @State private var showSettings = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if let f = model.forecast, let r = model.currentRating {
                current(f, r)
                if let st = model.station { measured(st) }
                if let t = model.tide { tideRow(t, f.timeZone) }
                Divider()
                windowsSection(f.timeZone)
                HourStrip(hours: Array(f.hours.prefix(24)), tz: f.timeZone)
            }
            if !model.status.isEmpty {
                Text(model.status).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if !model.nearby.isEmpty {
                Divider()
                nearbySection
            }
            Divider()
            searchSection
            if showSettings { settingsSection }
            footer
        }
        .padding(14)
        .frame(width: 340)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 1) {
                Text(model.spot?.name ?? "AirVibes").font(.title2.weight(.bold)).lineLimit(1)
                Text(model.pinned == nil ? "Nearest beach to you" : "Pinned spot")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if model.pinned != nil {
                Button("Use nearest") { model.pin(nil) }.buttonStyle(.link).font(.caption)
            }
        }
    }

    private func current(_ f: Forecast, _ r: (level: Level, why: String)) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(text: "Forecast now")
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(model.units.fmt(f.speed)).font(.system(size: 44, weight: .bold, design: .rounded))
                Text(model.units.label).font(.title3).foregroundStyle(.secondary)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(arrowChar(f.deg)) from \(dirName(f.deg)) \(Int(f.deg))°").font(.headline)
                    Text("gusting \(model.units.fmt(f.gust))").foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 8) {
                Pill(level: r.level)
                Text(r.why).font(.callout).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func measured(_ st: Station) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            SectionLabel(text: "Measured")
            if let deg = st.deg, st.speed > 0 {
                Text("\(model.units.fmt(st.speed)) \(model.units.label)\(st.gust.map { " gusting \(model.units.fmt($0))" } ?? "") · from \(dirName(deg))")
                    .font(.headline)
            } else {
                Text("Calm").font(.headline)
            }
            Text("\(st.name) · \(Int(st.dist.rounded())) km away · \(ago(st.time))").font(.caption).foregroundStyle(.secondary)
        }
    }

    private func tideRow(_ t: TideState, _ tz: TimeZone) -> some View {
        HStack(spacing: 10) {
            TideIcon(state: t)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(t.rising ? "Rising" : "Falling") · \(t.next.isHigh ? "high" : "low") \(clock(t.next.time, tz))").font(.headline)
                Text("\(t.after.map { "then \($0.isHigh ? "high" : "low") \(clock($0.time, tz)) · " } ?? "")modelled tide")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func windowsSection(_ tz: TimeZone) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionLabel(text: "Rideable windows")
            let w = model.windows.prefix(3)
            if w.isEmpty {
                Text("None in the next 3 days for your limits.").font(.callout).foregroundStyle(.secondary)
            }
            ForEach(Array(w)) { win in
                HStack {
                    Text("\(dayHour(win.start, tz))–\(clock(win.end, tz).replacingOccurrences(of: ":00", with: ""))").fontWeight(.semibold)
                    Spacer()
                    let lo = model.units.fmt(win.minSpeed), hi = model.units.fmt(win.maxSpeed)
                    Text("\(lo == hi ? lo : "\(lo)–\(hi)") \(model.units.label) \(dirName(win.deg))").foregroundStyle(.secondary)
                }
                .font(.callout)
            }
        }
    }

    private var nearbySection: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionLabel(text: "Nearby beaches")
            ForEach(model.nearby.prefix(6)) { b in
                let r = model.rating(speed: b.speed, gust: b.gust, deg: b.deg)
                Button {
                    model.pin(b.beach.spot)
                } label: {
                    HStack {
                        Circle().fill(r.level.color).frame(width: 8, height: 8)
                        Text(b.beach.name).lineLimit(1)
                        Spacer()
                        Text("\(arrowChar(b.deg)) \(model.units.fmt(b.speed)) g\(model.units.fmt(b.gust))")
                            .monospacedDigit().foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .font(.callout)
            }
        }
    }

    private var searchSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                TextField("Search a beach or town", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { search() }
                Button("Search") { search() }.disabled(query.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if searching { ProgressView().controlSize(.small) }
            ForEach(results) { p in
                Button {
                    model.pin(Spot(id: "p:\(p.id)", name: p.name, lat: p.latitude, lon: p.longitude))
                    results = []
                    query = ""
                } label: {
                    HStack {
                        Text(p.name)
                        Spacer()
                        Text([p.admin1, p.country_code].compactMap { $0 }.joined(separator: ", ")).foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .font(.callout)
            }
        }
    }

    private func search() {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        searching = true
        Task {
            results = (try? await WeatherAPI.searchPlaces(q)) ?? []
            searching = false
        }
    }

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Sport", selection: Binding(get: { model.sport }, set: { model.applySport($0) })) {
                ForEach(Sport.allCases) { Text($0.label).tag($0) }
            }
            Stepper("Min wind: \(Int(model.minWind)) kn", value: Binding(get: { model.minWind }, set: { model.minWind = $0; model.sport = .custom }), in: 0...50)
            Stepper("Max gust: \(Int(model.maxGust)) kn", value: Binding(get: { model.maxGust }, set: { model.maxGust = $0; model.sport = .custom }), in: 5...70)
            Picker("Units", selection: $model.units) {
                ForEach(Units.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
        }
        .font(.callout)
    }

    private var footer: some View {
        HStack {
            Button {
                Task { await model.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .disabled(model.loading)
            .help("Refresh")
            if model.loading { ProgressView().controlSize(.small) }
            else if let u = model.updated {
                Text("Updated \(clock(u, .current))").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button(showSettings ? "Done" : "Limits") { showSettings.toggle() }
            Button("Quit") { NSApplication.shared.terminate(nil) }
        }
        .buttonStyle(.borderless)
    }
}
