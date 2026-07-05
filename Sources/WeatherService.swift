import Foundation

/// Fetches the real current local weather (via wttr.in, which geolocates by
/// the machine's IP, so no location permission prompt) and caches a short
/// summary like "partly cloudy, 27\u{00B0}C right now". The temperature follows the
/// user's locale automatically (\u{00B0}C in most of the world, \u{00B0}F in the US),
/// respecting the system Region setting. The buddies use this when they chat
/// about the weather so the answer is actually accurate rather than a
/// hardcoded guess. Refreshes every 30 minutes; if a fetch fails the cached
/// value is left as-is (and stays nil until the first success, in which case
/// the buddies just talk about something else).
final class WeatherService {
    static let shared = WeatherService()

    private(set) var summary: String?
    /// Lowercased condition text from the last fetch, e.g. "light rain".
    private(set) var condition: String?
    private var timer: Timer?

    /// Whether it's currently raining (or drizzling / storming), for buddies
    /// to react to. False until the first successful fetch. Set the
    /// DOCKMATES_FORCE_RAIN env var to preview the rain reaction on demand.
    var isRaining: Bool {
        if ProcessInfo.processInfo.environment["DOCKMATES_FORCE_RAIN"] != nil { return true }
        guard let c = condition else { return false }
        return ["rain", "drizzle", "shower", "thunder", "sleet"].contains { c.contains($0) }
    }

    func start() {
        refresh()
        let t = Timer(timeInterval: 30 * 60, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func refresh() {
        guard let url = URL(string: "https://wttr.in/?format=j1") else { return }
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        // wttr.in serves an HTML page to browser-like agents; a curl-style
        // User-Agent is what gets the JSON payload.
        request.setValue("curl/8", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let current = (json["current_condition"] as? [[String: Any]])?.first,
                  let tempCString = current["temp_C"] as? String,
                  let tempC = Double(tempCString),
                  let descValue = (current["weatherDesc"] as? [[String: Any]])?
                      .first?["value"] as? String else { return }
            let desc = descValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !desc.isEmpty else { return }

            // wttr gives Celsius; MeasurementFormatter (default options, current
            // locale) converts it to the user's preferred temperature unit and
            // appends the right label, e.g. "27°C" or "81°F".
            let formatter = MeasurementFormatter()
            formatter.numberFormatter.maximumFractionDigits = 0
            let tempStr = formatter.string(from: Measurement(value: tempC, unit: UnitTemperature.celsius))

            let summary = "\(desc), \(tempStr) right now"
            DispatchQueue.main.async {
                self?.summary = summary
                self?.condition = desc
            }
        }.resume()
    }
}
