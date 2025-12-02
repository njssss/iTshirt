import SwiftUI

final class VM: ObservableObject {
    @Published var isRunning = false
    @Published var isFocus = true
    @Published var seconds = 25*60
    @Published var todayMinutes = 0

    var focusMinutes = 25
    var breakMinutes = 5

    private var timer: Timer?
    private let keyToday = "SFT_today"
    private let keyDate = "SFT_date"

    init() { loadToday(); seconds = focusMinutes * 60 }

    private func todayKeyDateString() -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    private func loadToday() {
        let ud = UserDefaults.standard
        let savedDate = ud.string(forKey: keyDate) ?? ""
        let today = todayKeyDateString()
        if savedDate != today {
            todayMinutes = 0
            ud.set(today, forKey: keyDate)
            ud.set(0, forKey: keyToday)
        } else {
            todayMinutes = ud.integer(forKey: keyToday)
        }
    }

    private func saveToday() {
        let ud = UserDefaults.standard
        ud.set(todayMinutes, forKey: keyToday)
        ud.set(todayKeyDateString(), forKey: keyDate)
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            DispatchQueue.main.async { self?.tick() }
        }
    }

    func pause() {
        isRunning = false
        timer?.invalidate()
        timer = nil
    }

    func reset() {
        pause()
        isFocus = true
        seconds = focusMinutes * 60
    }

    private func tick() {
        guard seconds > 0 else {
            completeIfFocus()
            switchMode()
            return
        }
        seconds -= 1
    }

    private func switchMode() {
        isFocus.toggle()
        seconds = (isFocus ? focusMinutes : breakMinutes) * 60
    }

    private func completeIfFocus() {
        if isFocus {
            todayMinutes += focusMinutes
            saveToday()
        }
    }
}

