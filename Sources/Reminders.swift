import Foundation

struct Reminder: Codable {
    var id = UUID()
    var message: String
    var isInterval: Bool
    var intervalMinutes: Int
    var hour: Int
    var minute: Int
    var enabled = true

    var scheduleText: String {
        if isInterval {
            let h = intervalMinutes / 60
            let m = intervalMinutes % 60
            if h > 0 && m > 0 { return "every \(h)h \(m)m" }
            if h > 0 { return "every \(h)h" }
            return "every \(m)m"
        } else {
            let hr12 = ((hour + 11) % 12) + 1
            let ampm = hour < 12 ? "am" : "pm"
            return String(format: "at %d:%02d %@", hr12, minute, ampm)
        }
    }
}

/// Keeps the reminder list in UserDefaults and fires them on a coarse timer.
/// Delivery is delegated; if the delegate can't deliver right now (all
/// buddies busy), the reminder stays pending and is retried on the next tick.
final class ReminderScheduler {
    private static let storageKey = "reminders"

    private(set) var reminders: [Reminder] = []
    var deliver: ((Reminder) -> Bool)?

    private var lastFired: [UUID: Date] = [:]
    private var timer: Timer?
    private let calendar = Calendar.current

    init() {
        load()
    }

    func start() {
        let timer = Timer(timeInterval: 20, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        // Interval reminders start counting from launch
        let now = Date()
        for r in reminders where r.isInterval {
            lastFired[r.id] = now
        }
    }

    func add(_ reminder: Reminder) {
        reminders.append(reminder)
        lastFired[reminder.id] = Date()
        save()
    }

    func update(_ reminder: Reminder) {
        if let index = reminders.firstIndex(where: { $0.id == reminder.id }) {
            reminders[index] = reminder
            save()
        }
    }

    /// Restart a reminder's clock (used when it gets re-enabled).
    func touch(_ id: UUID) {
        lastFired[id] = Date()
    }

    func remove(id: UUID) {
        reminders.removeAll { $0.id == id }
        lastFired[id] = nil
        save()
    }

    /// Test/preview helper: set reminders without persisting.
    func useSampleData(_ list: [Reminder]) {
        reminders = list
    }

    private func tick() {
        let now = Date()
        for reminder in reminders where reminder.enabled {
            if reminder.isInterval {
                guard let last = lastFired[reminder.id] else {
                    lastFired[reminder.id] = now
                    continue
                }
                if now.timeIntervalSince(last) >= TimeInterval(reminder.intervalMinutes * 60) {
                    if deliver?(reminder) == true {
                        lastFired[reminder.id] = now
                    }
                }
            } else {
                var comps = calendar.dateComponents([.year, .month, .day], from: now)
                comps.hour = reminder.hour
                comps.minute = reminder.minute
                guard let target = calendar.date(from: comps) else { continue }
                let last = lastFired[reminder.id] ?? .distantPast
                guard now >= target, last < target else { continue }
                if now.timeIntervalSince(target) > 90 * 60 {
                    // Way past it (Mac was probably asleep); skip today
                    lastFired[reminder.id] = target
                } else if deliver?(reminder) == true {
                    lastFired[reminder.id] = now
                }
            }
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(reminders) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let list = try? JSONDecoder().decode([Reminder].self, from: data) {
            reminders = list
        }
    }
}
