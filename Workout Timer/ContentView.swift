import SwiftUI
import Combine
import AudioToolbox
import AVFoundation


// MARK: - Timer Model
class TimerModel: ObservableObject {
    @Published var workTime: Int = 180 // 3 minutes in seconds
    @Published var restTime: Int = 60  // 1 minute in seconds
    @Published var currentTime: Int = 180
    @Published var isRunning: Bool = false
    @Published var isWorkPhase: Bool = true
    @Published var round: Int = 1
    
    private var timer: AnyCancellable?
    private var audioPlayer: AVAudioPlayer?
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    
    // Track when timer was started for background calculation
    private var timerStartDate: Date?
    private var lastKnownCurrentTime: Int = 180
    
    init() {
        // Setup notifications for app state changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
    }
    
    @objc private func appDidEnterBackground() {
        if isRunning {
            // Request background task
            backgroundTask = UIApplication.shared.beginBackgroundTask { [weak self] in
                self?.endBackgroundTask()
            }
        }
    }
    
    @objc private func appWillEnterForeground() {
        if isRunning {
            updateTimerFromBackground()
        }
        endBackgroundTask()
    }
    
    private func endBackgroundTask() {
        if backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }
    }
    
    private func updateTimerFromBackground() {
        guard let startDate = timerStartDate else { return }
        
        let elapsedTime = Int(Date().timeIntervalSince(startDate))
        var remainingTime = lastKnownCurrentTime - elapsedTime
        
        // Calculate phase changes that happened during background
        while remainingTime <= 0 {
            if isWorkPhase {
                playBeepSound()
                isWorkPhase = false
                remainingTime += restTime
            } else {
                playRoundEndSound()
                isWorkPhase = true
                remainingTime += workTime
                round += 1
            }
        }
        
        currentTime = remainingTime
        lastKnownCurrentTime = remainingTime
        timerStartDate = Date()
    }
    
    func startTimer() {
        isRunning = true
        timerStartDate = Date()
        lastKnownCurrentTime = currentTime
        
        timer = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.tick()
            }
        
        // Configure audio session for background playback
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to set audio session category: \(error)")
        }
    }
    
    func pauseTimer() {
        isRunning = false
        timer?.cancel()
        timerStartDate = nil
        endBackgroundTask()
    }
    
    func resetTimer() {
        isRunning = false
        timer?.cancel()
        isWorkPhase = true
        currentTime = workTime
        round = 1
        timerStartDate = nil
        lastKnownCurrentTime = workTime
        endBackgroundTask()
    }
    
    private func tick() {
        if currentTime > 0 {
            currentTime -= 1
            lastKnownCurrentTime = currentTime
        } else {
            // Switch phases
            if isWorkPhase {
                // Work phase ending - play regular beep
                playBeepSound()
                isWorkPhase = false
                currentTime = restTime
                lastKnownCurrentTime = restTime
            } else {
                // Rest phase ending - play custom sound for new round
                playRoundEndSound()
                isWorkPhase = true
                currentTime = workTime
                lastKnownCurrentTime = workTime
                round += 1
            }
            timerStartDate = Date()
        }
    }
    
    private func playBeepSound() {
        // Play system sound for work phase end
        playRoundEndSound()
        
        // Light haptic feedback for phase change
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
    }
    
    private func playRoundEndSound() {
        // Try to play custom sound first
        if let soundURL = Bundle.main.url(forResource: "round_end", withExtension: "mp3") {
            do {
                audioPlayer = try AVAudioPlayer(contentsOf: soundURL)
                audioPlayer?.play()
            } catch {
                print("Error playing custom sound: \(error)")
                // Fallback to system sound
                AudioServicesPlaySystemSound(1052) // Different system sound for rounds
            }
        } else {
            // Fallback to system sound if custom file not found
            playRoundEndSound() // Different system sound for rounds
        }
        
        // Strong haptic feedback for round completion
        let impactFeedback = UIImpactFeedbackGenerator(style: .heavy)
        impactFeedback.impactOccurred()
    }
    
    func updateWorkTime(minutes: Int, seconds: Int) {
        let totalSeconds = minutes * 60 + seconds
        workTime = totalSeconds
        if isWorkPhase && !isRunning {
            currentTime = totalSeconds
        }
    }
    
    func updateRestTime(minutes: Int, seconds: Int) {
        let totalSeconds = minutes * 60 + seconds
        restTime = totalSeconds
        if !isWorkPhase && !isRunning {
            currentTime = totalSeconds
        }
    }
    
    var workMinutes: Int { workTime / 60 }
    var workSeconds: Int { workTime % 60 }
    var restMinutes: Int { restTime / 60 }
    var restSecondsValue: Int { restTime % 60 }
    
    var progress: Double {
        if isWorkPhase {
            return Double(workTime - currentTime) / Double(workTime)
        } else {
            return Double(restTime - currentTime) / Double(restTime)
        }
    }
    
    func formatTime(_ seconds: Int) -> String {
        let mins = seconds / 60
        let secs = seconds % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}

// MARK: - Content View
struct ContentView: View {
    @StateObject private var timerModel = TimerModel()
    @State private var showSettings = false
    
    var body: some View {
        NavigationView {
            TimerView(timerModel: timerModel, showSettings: $showSettings)
                .sheet(isPresented: $showSettings) {
                    SettingsView(timerModel: timerModel, isPresented: $showSettings)
                }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
}

// MARK: - Timer View
struct TimerView: View {
    @ObservedObject var timerModel: TimerModel
    @Binding var showSettings: Bool
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 30) {
                Spacer()
                
                // Round Counter
                HStack {
                    Text("Round")
                        .font(.title2)
                        .foregroundColor(.gray)
                    Text("\(timerModel.round)")
                        .font(.system(size: 48, weight: .light))
                        .foregroundColor(.white)
                }
                
                // Phase Indicator
                Text(timerModel.isWorkPhase ? "WORK" : "REST")
                    .font(.title2)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(
                        Capsule()
                            .fill(timerModel.isWorkPhase ? Color.green : Color.blue)
                    )
                
                // Circular Progress Timer
                ZStack {
                    // Background circle
                    Circle()
                        .stroke(Color.white.opacity(0.1), lineWidth: 4)
                        .frame(width: 300, height: 300)
                    
                    // Progress circle
                    Circle()
                        .trim(from: 0, to: timerModel.progress)
                        .stroke(
                            timerModel.isWorkPhase ? Color.green : Color.blue,
                            style: StrokeStyle(lineWidth: 4, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .frame(width: 300, height: 300)
                        .animation(.linear(duration: 1), value: timerModel.progress)
                    
                    // Time display
                    Text(timerModel.formatTime(timerModel.currentTime))
                        .font(.system(size: 64, weight: .ultraLight, design: .monospaced))
                        .foregroundColor(.white)
                }
                
                Spacer()
                
                // Control Buttons
                HStack(spacing: 40) {
                    // Reset Button
                    Button(action: timerModel.resetTimer) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 32))
                            .foregroundColor(.white)
                            .frame(width: 64, height: 64)
                            .background(Color.gray.opacity(0.3))
                            .clipShape(Circle())
                    }
                    
                    // Play/Pause Button
                    Button(action: {
                        if timerModel.isRunning {
                            timerModel.pauseTimer()
                        } else {
                            timerModel.startTimer()
                        }
                    }) {
                        Image(systemName: timerModel.isRunning ? "pause.fill" : "play.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.white)
                            .frame(width: 80, height: 80)
                            .background(timerModel.isRunning ? Color.red : Color.green)
                            .clipShape(Circle())
                    }
                    
                    // Settings Button
                    Button(action: { showSettings = true }) {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 32))
                            .foregroundColor(.white)
                            .frame(width: 64, height: 64)
                            .background(Color.gray.opacity(0.3))
                            .clipShape(Circle())
                    }
                }
                .padding(.bottom, 40)
            }
        }
        .navigationBarHidden(true)
    }
}

// MARK: - Settings View
struct SettingsView: View {
    @ObservedObject var timerModel: TimerModel
    @Binding var isPresented: Bool
    
    @State private var workMinutes: Int
    @State private var workSeconds: Int
    @State private var restMinutes: Int
    @State private var restSeconds: Int
    
    init(timerModel: TimerModel, isPresented: Binding<Bool>) {
        self.timerModel = timerModel
        self._isPresented = isPresented
        self._workMinutes = State(initialValue: timerModel.workMinutes)
        self._workSeconds = State(initialValue: timerModel.workSeconds)
        self._restMinutes = State(initialValue: timerModel.restMinutes)
        self._restSeconds = State(initialValue: timerModel.restSecondsValue)
    }
    
    // Update timer values whenever picker values change
    private func updateTimerValues() {
        timerModel.updateWorkTime(minutes: workMinutes, seconds: workSeconds)
        timerModel.updateRestTime(minutes: restMinutes, seconds: restSeconds)
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                
                VStack(spacing: 40) {
                    // Work Time Setting
                    VStack(spacing: 20) {
                        Text("Work Time")
                            .font(.title)
                            .fontWeight(.medium)
                            .foregroundColor(.green)
                        
                        HStack(spacing: 40) {
                            VStack {
                                Text("min")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                
                                Picker("Minutes", selection: $workMinutes) {
                                    ForEach(0...59, id: \.self) { minute in
                                        Text("\(minute)")
                                            .font(.title2)
                                            .tag(minute)
                                    }
                                }
                                .pickerStyle(WheelPickerStyle())
                                .frame(width: 80, height: 150)
                                .clipped()
                                .onChange(of: workMinutes) {
                                    updateTimerValues()
                                }
                            }
                            
                            VStack {
                                Text("sec")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                
                                Picker("Seconds", selection: $workSeconds) {
                                    ForEach(0...59, id: \.self) { second in
                                        Text("\(second)")
                                            .font(.title2)
                                            .tag(second)
                                    }
                                }
                                .pickerStyle(WheelPickerStyle())
                                .frame(width: 80, height: 150)
                                .clipped()
                            .onChange(of: workSeconds){
                                updateTimerValues()
                                }
                            }
                        }
                        
                        Text(timerModel.formatTime(workMinutes * 60 + workSeconds))
                            .font(.title2)
                            .foregroundColor(.gray)
                    }
                    
                    // Rest Time Setting
                    VStack(spacing: 20) {
                        Text("Rest Time")
                            .font(.title)
                            .fontWeight(.medium)
                            .foregroundColor(.blue)
                        
                        HStack(spacing: 40) {
                            VStack {
                                Text("min")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                
                                Picker("Minutes", selection: $restMinutes) {
                                    ForEach(0...59, id: \.self) { minute in
                                        Text("\(minute)")
                                            .font(.title2)
                                            .tag(minute)
                                    }
                                }
                                .pickerStyle(WheelPickerStyle())
                                .frame(width: 80, height: 150)
                                .clipped()
                                .onChange(of: restMinutes) {
                                    updateTimerValues()
                                }
                            }
                            
                            VStack {
                                Text("sec")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                
                                Picker("Seconds", selection: $restSeconds) {
                                    ForEach(0...59, id: \.self) { second in
                                        Text("\(second)")
                                            .font(.title2)
                                            .tag(second)
                                    }
                                }
                                .pickerStyle(WheelPickerStyle())
                                .frame(width: 80, height: 150)
                                .clipped()
                                .onChange(of: restSeconds) {
                                    updateTimerValues()
                                }
                            }
                        }
                        
                        Text(timerModel.formatTime(restMinutes * 60 + restSeconds))
                            .font(.title2)
                            .foregroundColor(.gray)
                    }
                    
                    Spacer()
                }
                .padding()
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                leading: Button("Back") {
                    isPresented = false
                }
                .foregroundColor(.blue)
            )
        }
        .onDisappear {
            // This ensures timer values are updated when sheet is dismissed by any method
            updateTimerValues()
        }
    }
}

// MARK: - Preview
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .preferredColorScheme(.dark)
    }
}
