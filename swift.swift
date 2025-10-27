import SwiftUI

// -----------------------------
// MARK: - Models
// -----------------------------

/// 물 섭취 단일 기록
struct DrinkRecord: Identifiable, Codable {
    let id: UUID
    let date: Date
    let amount: Int // ml
    
    init(amount: Int, date: Date = Date()) {
        self.id = UUID()
        self.date = date
        self.amount = amount
    }
}

/// 하루 요약 (이력 저장용)
struct DailySummary: Identifiable, Codable {
    let id: UUID
    let dayIdentifier: String // "yyyy-MM-dd" (지역시간 기준)
    let target: Int
    let total: Int
    let records: [DrinkRecord]
    
    init(dayIdentifier: String, target: Int, total: Int, records: [DrinkRecord]) {
        self.id = UUID()
        self.dayIdentifier = dayIdentifier
        self.target = target
        self.total = total
        self.records = records
    }
}

// -----------------------------
// MARK: - Persistence (simple UserDefaults + Codable)
// -----------------------------

final class Persistence {
    static let shared = Persistence()
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let defaults = UserDefaults.standard
    
    private init() {
        // Set encoder/decoder date strategy if needed
    }
    
    private enum Keys {
        static let settings = "WaterTrack.Settings"
        static let todayData = "WaterTrack.TodayData"
        static let history = "WaterTrack.History"
    }
    
    // Save generic Codable
    private func save<T: Codable>(_ value: T, key: String) {
        if let data = try? encoder.encode(value) {
            defaults.set(data, forKey: key)
        }
    }
    
    private func load<T: Codable>(_ type: T.Type, key: String) -> T? {
        guard let data = defaults.data(forKey: key),
              let value = try? decoder.decode(type, from: data) else { return nil }
        return value
    }
    
    // Settings
    func saveSettings(_ s: SettingsModel) { save(s, key: Keys.settings) }
    func loadSettings() -> SettingsModel? { load(SettingsModel.self, key: Keys.settings) }
    
    // Today's transient data (target/records/lastDayId)
    func saveTodayData(_ d: TodayData) { save(d, key: Keys.todayData) }
    func loadTodayData() -> TodayData? { load(TodayData.self, key: Keys.todayData) }
    
    // History array
    func saveHistory(_ arr: [DailySummary]) { save(arr, key: Keys.history) }
    func loadHistory() -> [DailySummary] { load([DailySummary].self, key: Keys.history) ?? [] }
}

// -----------------------------
// MARK: - Settings & TodayData
// -----------------------------

/// 사용자가 변경 가능한 설정 (persisted)
struct SettingsModel: Codable {
    var defaultTarget: Int // ml
    var quickAmounts: [Int]
    var autoResetAtMidnight: Bool
    var notificationsEnabled: Bool // placeholder
}

/// 오늘의 데이터 (persisted minimally to maintain across launches)
struct TodayData: Codable {
    var target: Int
    var records: [DrinkRecord]
    var lastSavedDayIdentifier: String // for reset detection
}

// -----------------------------
// MARK: - Utilities
// -----------------------------

/// Day identifier in Asia/Seoul timezone (yyyy-MM-dd)
func dayIdentifier(for date: Date = Date()) -> String {
    let df = DateFormatter()
    df.timeZone = TimeZone(identifier: "Asia/Seoul")
    df.dateFormat = "yyyy-MM-dd"
    return df.string(from: date)
}

/// Time string like "09:15"
func timeString(from date: Date) -> String {
    let df = DateFormatter()
    df.timeZone = TimeZone(identifier: "Asia/Seoul")
    df.dateFormat = "HH:mm"
    return df.string(from: date)
}

// -----------------------------
// MARK: - ViewModels
// -----------------------------

final class TodaySummaryViewModel: ObservableObject {
    // Published props for UI binding
    @Published var target: Int
    @Published private(set) var total: Int
    @Published private(set) var records: [DrinkRecord]
    
    // History (saved summaries)
    @Published var history: [DailySummary]
    
    // Settings
    @Published var settings: SettingsModel
    
    private let persistence = Persistence.shared
    
    init() {
        // Load settings or defaults
        if let s = persistence.loadSettings() {
            settings = s
        } else {
            settings = SettingsModel(defaultTarget: 2000, quickAmounts: [100, 200, 350], autoResetAtMidnight: true, notificationsEnabled: false)
            persistence.saveSettings(settings)
        }
        
        // Load today data and history
        if let t = persistence.loadTodayData() {
            target = t.target
            records = t.records
        } else {
            target = settings.defaultTarget
            records = []
        }
        total = records.reduce(0) { $0 + $1.amount }
        history = persistence.loadHistory()
        
        // Automatic daily reset check
        resetIfNeeded()
    }
    
    // MARK: - Core actions
    
    /// 음수 입력을 막고 범위를 안전하게 처리
    func add(amount: Int) {
        guard amount > 0 else { return }
        let record = DrinkRecord(amount: amount)
        records.insert(record, at: 0) // 최신이 위
        total += amount
        saveToday()
    }
    
    /// 수동 초기화: 오늘 기록을 이력으로 옮기고 새로 시작
    func manualReset(confirm: Bool = true) {
        guard !records.isEmpty else {
            // 아무것도 없으면 그냥 리셋(간단)
            resetTodayStorage()
            return
        }
        // confirm 파라미터은 호출 측에서 알림 처리 후 true로 전달하면 실제로 초기화
        if confirm {
            archiveTodayAndReset()
        }
    }
    
    /// 자동 초기화: 앱 실행/포그라운드 진입 시 호출
    func resetIfNeeded() {
        let currentDayId = dayIdentifier()
        if let todayData = persistence.loadTodayData() {
            if todayData.lastSavedDayIdentifier != currentDayId && settings.autoResetAtMidnight {
                // 이전 날짜가 있다면 아카이브 후 reset
                archiveTodayAndReset()
            } else {
                // 동일 날짜면 nothing
                // but ensure target is synchronized with settings.default
                if target != todayData.target {
                    target = todayData.target
                }
            }
        } else {
            // No stored today data: initialize with settings.defaultTarget
            target = settings.defaultTarget
            records = []
            total = 0
            saveToday()
        }
    }
    
    /// 목표 변경
    func updateTarget(to newTarget: Int) {
        guard newTarget > 0 else { return }
        target = newTarget
        saveToday()
        settings.defaultTarget = newTarget
        persistence.saveSettings(settings)
    }
    
    /// 기록 삭제
    func deleteRecord(at offsets: IndexSet) {
        for idx in offsets {
            total -= records[idx].amount
        }
        records.remove(atOffsets: offsets)
        saveToday()
    }
    
    // MARK: - Persistence helpers
    
    private func saveToday() {
        let today = TodayData(target: target, records: records, lastSavedDayIdentifier: dayIdentifier())
        persistence.saveTodayData(today)
    }
    
    private func resetTodayStorage() {
        target = settings.defaultTarget
        records = []
        total = 0
        saveToday()
    }
    
    private func archiveTodayAndReset() {
        // Create DailySummary with today's data and push to history if any records exist
        let currentDayId = persistence.loadTodayData()?.lastSavedDayIdentifier ?? dayIdentifier()
        let archived = DailySummary(dayIdentifier: currentDayId, target: target, total: total, records: records)
        if !records.isEmpty {
            history.insert(archived, at: 0)
            persistence.saveHistory(history)
        }
        resetTodayStorage()
    }
}

// -----------------------------
// MARK: - Views
// -----------------------------

@main
struct WaterTrackApp: App {
    @StateObject private var vm = TodaySummaryViewModel()
    
    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environmentObject(vm)
        }
    }
}

struct MainTabView: View {
    @EnvironmentObject var vm: TodaySummaryViewModel
    
    var body: some View {
        TabView {
            HomeView()
                .tabItem {
                    Label("홈", systemImage: "drop.fill")
                }
            HistoryView()
                .tabItem {
                    Label("기록", systemImage: "list.bullet")
                }
            SettingsView()
                .tabItem {
                    Label("설정", systemImage: "gearshape")
                }
        }
        .onAppear {
            vm.resetIfNeeded() // 앱 실행 시 자동 리셋 확인
        }
    }
}

struct HomeView: View {
    @EnvironmentObject var vm: TodaySummaryViewModel
    @State private var showCustomAdd = false
    @State private var customAmountText: String = ""
    @State private var showResetAlert = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // 날짜 & 목표 요약
                VStack {
                    Text(todayDateString())
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text("\(vm.total) / \(vm.target) ml")
                        .font(.title2)
                        .bold()
                }
                
                // 원형 진행률 (Ring)
                RingView(progress: progressFraction())
                    .frame(width: 180, height: 180)
                
                // 빠른 추가 버튼들
                HStack(spacing: 16) {
                    ForEach(vm.settings.quickAmounts, id: \.self) { amt in
                        Button(action: {
                            vm.add(amount: amt)
                        }) {
                            Text("+\(amt)")
                                .frame(width: 68, height: 44)
                                .background(.ultraThinMaterial)
                                .cornerRadius(10)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding(.horizontal)
                
                // 사용자 지정 추가
                HStack {
                    Button(action: { showCustomAdd.toggle() }) {
                        Label("사용자 지정 추가", systemImage: "plus.circle")
                    }
                    Spacer()
                    Button(role: .destructive) {
                        showResetAlert = true
                    } label: {
                        Label("오늘 초기화", systemImage: "arrow.counterclockwise")
                    }
                }
                .padding(.horizontal)
                
                // 최근 기록 미리보기
                VStack(alignment: .leading, spacing: 8) {
                    Text("최근 기록")
                        .font(.headline)
                    if vm.records.isEmpty {
                        Text("아직 기록이 없습니다.")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(vm.records.prefix(4)) { record in
                            HStack {
                                Text(timeString(from: record.date))
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text("+\(record.amount) ml")
                            }
                        }
                    }
                }
                .padding()
                Spacer()
            }
            .navigationTitle("WaterTrack")
            .sheet(isPresented: $showCustomAdd) {
                CustomAddSheet(isPresented: $showCustomAdd, onAdd: { amt in
                    vm.add(amount: amt)
                })
            }
            .alert("오늘 기록을 초기화하시겠습니까?", isPresented: $showResetAlert) {
                Button("초기화", role: .destructive) {
                    vm.manualReset(confirm: true)
                }
                Button("취소", role: .cancel) { }
            }
            .padding(.top)
        }
    }
    
    private func progressFraction() -> Double {
        guard vm.target > 0 else { return 0 }
        return min(Double(vm.total) / Double(vm.target), 1.0)
    }
    
    private func todayDateString() -> String {
        let df = DateFormatter()
        df.timeZone = TimeZone(identifier: "Asia/Seoul")
        df.dateStyle = .medium
        return df.string(from: Date())
    }
}

struct CustomAddSheet: View {
    @Binding var isPresented: Bool
    @State private var amountText: String = ""
    var onAdd: (Int) -> Void
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("물 양 (ml)")) {
                    TextField("예: 250", text: $amountText)
                        .keyboardType(.numberPad)
                }
                Section {
                    Button("추가") {
                        if let val = Int(amountText), val > 0 {
                            onAdd(val)
                            isPresented = false
                        }
                    }
                    Button("취소", role: .cancel) {
                        isPresented = false
                    }
                }
            }
            .navigationTitle("사용자 지정 추가")
        }
    }
}

struct HistoryView: View {
    @EnvironmentObject var vm: TodaySummaryViewModel
    
    var body: some View {
        NavigationView {
            List {
                // 오늘 항목 (실시간)
                if !vm.records.isEmpty {
                    Section(header: Text("오늘")) {
                        ForEach(vm.records) { record in
                            HStack {
                                Text(timeString(from: record.date))
                                Spacer()
                                Text("+\(record.amount) ml")
                            }
                        }
                        .onDelete(perform: vm.deleteRecord)
                    }
                }
                
                // 이전 날짜들 (history)
                ForEach(vm.history) { day in
                    Section(header: Text(dayTitle(from: day.dayIdentifier))) {
                        ForEach(day.records) { r in
                            HStack {
                                Text(timeString(from: r.date))
                                Spacer()
                                Text("+\(r.amount) ml")
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("기록")
            .toolbar {
                EditButton()
            }
        }
    }
    
    private func dayTitle(from id: String) -> String {
        // id 예: "2025-10-27" -> 가독성 있게 변경
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.timeZone = TimeZone(identifier: "Asia/Seoul")
        if let d = df.date(from: id) {
            let out = DateFormatter()
            out.dateStyle = .medium
            out.timeZone = TimeZone(identifier: "Asia/Seoul")
            return out.string(from: d)
        }
        return id
    }
}

struct SettingsView: View {
    @EnvironmentObject var vm: TodaySummaryViewModel
    @State private var newTargetText: String = ""
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("목표")) {
                    HStack {
                        Text("오늘 목표")
                        Spacer()
                        Text("\(vm.target) ml")
                            .foregroundColor(.secondary)
                    }
                    TextField("기본 목표 입력(ml)", text: $newTargetText)
                        .keyboardType(.numberPad)
                    Button("목표 변경") {
                        if let v = Int(newTargetText), v > 0 {
                            vm.updateTarget(to: v)
                            newTargetText = ""
                        }
                    }
                }
                
                Section(header: Text("빠른 추가 버튼")) {
                    ForEach(vm.settings.quickAmounts.indices, id: \.self) { idx in
                        HStack {
                            Text("\(vm.settings.quickAmounts[idx]) ml")
                            Spacer()
                        }
                    }
                }
                
                Section {
                    Toggle("자정 자동 초기화", isOn: $vm.settings.autoResetAtMidnight)
                        .onChange(of: vm.settings.autoResetAtMidnight) { _ in
                            Persistence.shared.saveSettings(vm.settings)
                        }
                }
            }
            .navigationTitle("설정")
        }
    }
}

// -----------------------------
// MARK: - Small UI: RingView (원형 진행률)
// -----------------------------

struct RingView: View {
    var progress: Double // 0.0 ~ 1.0
    
    var body: some View {
        ZStack {
            // Background circle
            Circle()
                .stroke(lineWidth: 14)
                .opacity(0.2)
                .frame(width: 160, height: 160)
            // Progress circle
            Circle()
                .trim(from: 0, to: CGFloat(progress))
                .stroke(style: StrokeStyle(lineWidth: 14, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 160, height: 160)
                .animation(.easeOut(duration: 0.5), value: progress)
            
            // Center text
            VStack {
                Text("\(Int(progress * 100))%")
                    .font(.title)
                    .bold()
                Text("달성률")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// -----------------------------
// MARK: - Preview
// -----------------------------

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        MainTabView()
            .environmentObject(TodaySummaryViewModel())
    }
}
