import Foundation

/// Fetches the real current local weather (via wttr.in, which geolocates by
/// the machine's IP, so no location permission prompt) and caches a short
/// summary like "partly cloudy, 27\u{00B0} right now". The buddies use this when
/// they chat about the weather so the answer is actually accurate rather than
/// a hardcoded guess. Refreshes every 30 minutes; if a fetch fails the cached
/// value is left as-is (and stays nil until the first success, in which case
/// the buddies just talk about something else).
final class WeatherService {
    static let shared = WeatherService()

    private(set) var summary: String?
    private var timer: Timer?

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
                  let tempC = current["temp_C"] as? String,
                  let descValue = (current["weatherDesc"] as? [[String: Any]])?
                      .first?["value"] as? String else { return }
            let desc = descValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !desc.isEmpty, !tempC.isEmpty else { return }
            let summary = "\(desc), \(tempC)\u{00B0} right now"
            DispatchQueue.main.async { self?.summary = summary }
        }.resume()
    }
}
