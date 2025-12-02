
import SwiftUI

struct ContentView: View {
    @StateObject private var vm = VM()
    @State private var custom = ""

    var body: some View {
        VStack(spacing: 16) {
            Text(vm.isFocus ? "집중 모드" : "휴식 모드")
                .font(.headline)

            Text(timeString(vm.seconds))
                .font(.system(size: 56, design: .monospaced))

            HStack {
                Button(vm.isRunning ? "일시정지" : "시작") {
                    vm.isRunning ? vm.pause() : vm.start()
                }
                .buttonStyle(.borderedProminent)

                Button("초기화") { vm.reset() }
                    .buttonStyle(.bordered)
            }

            HStack {
                Button("25/5") {
                    vm.focusMinutes = 25
                    vm.breakMinutes = 5
                    vm.reset()
                }
                Button("50/10") {
                    vm.focusMinutes = 50
                    vm.breakMinutes = 10
                    vm.reset()
                }
                HStack {
                    TextField("분", text: $custom)
                        .keyboardType(.numberPad)
                        .frame(width: 50)
                        .textFieldStyle(.roundedBorder)

                    Button("설정") {
                        if let m = Int(custom), m > 0 {
                            vm.focusMinutes = m
                            vm.breakMinutes = 5
                            vm.reset()
                            custom = ""
                        }
                    }
                }
            }
            Spacer()

            VStack(alignment: .leading) {
                Text("오늘 누적 집중")
                    .font(.caption)
                Text("\(vm.todayMinutes) 분")
                    .font(.title2)
                    .bold()
            }

            Spacer()
        }
        .padding()
    }

    private func timeString(_ s: Int) -> String {
        String(format: "%02d:%02d", s/60, s%60)
    }
}

#Preview {
    ContentView()
}
