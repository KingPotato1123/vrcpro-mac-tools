// VRC HUD — 화면 오른쪽 위에 CPU·GPU·메모리, 게임 프로세스, 조종기 입력 Hz를 띄우는 작은 오버레이
// 빌드: swiftc -O main.swift -o "VRC HUD" -framework Cocoa -framework IOKit
import Cocoa
import IOKit
import IOKit.hid
import Darwin

// MARK: - 측정

final class CPUMeter {
    private var prev: [UInt32] = []
    func sample() -> Double {
        var count: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &count, &info, &infoCount) == KERN_SUCCESS,
              let info else { return 0 }
        defer { vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride)) }
        let cur = (0..<Int(infoCount)).map { UInt32(bitPattern: info[$0]) }
        defer { prev = cur }
        guard prev.count == cur.count else { return 0 }
        var busy: UInt64 = 0, total: UInt64 = 0
        for c in 0..<Int(count) {
            let b = c * Int(CPU_STATE_MAX)
            let d = (0..<Int(CPU_STATE_MAX)).map { UInt64(cur[b + $0] &- prev[b + $0]) }
            busy += d[Int(CPU_STATE_USER)] + d[Int(CPU_STATE_SYSTEM)] + d[Int(CPU_STATE_NICE)]
            total += d.reduce(0, +)
        }
        return total > 0 ? Double(busy) / Double(total) * 100 : 0
    }
}

func gpuUtilization() -> Double {
    var iter: io_iterator_t = 0
    guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iter) == KERN_SUCCESS else { return 0 }
    defer { IOObjectRelease(iter) }
    var best = 0.0
    while case let s = IOIteratorNext(iter), s != 0 {
        defer { IOObjectRelease(s) }
        if let stats = IORegistryEntryCreateCFProperty(s, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? [String: Any],
           let v = stats["Device Utilization %"] as? Int {
            best = max(best, Double(v))
        }
    }
    return best
}

struct MemInfo { var usedGB: Double; var totalGB: Double; var swapGB: Double }

func memoryInfo() -> MemInfo {
    var stats = vm_statistics64()
    var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
    let page = Double(vm_kernel_page_size)
    _ = withUnsafeMutablePointer(to: &stats) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count) }
    }
    // 활성 상태 보기의 "사용된 메모리"와 같은 기준: 앱 메모리 + 고정 + 압축
    let app = Double(stats.internal_page_count) - Double(stats.purgeable_count)
    let used = (app + Double(stats.wire_count) + Double(stats.compressor_page_count)) * page
    var swap = xsw_usage()
    var size = MemoryLayout<xsw_usage>.size
    sysctlbyname("vm.swapusage", &swap, &size, nil, 0)
    let gb = 1024.0 * 1024 * 1024
    return MemInfo(usedGB: used / gb, totalGB: Double(ProcessInfo.processInfo.physicalMemory) / gb, swapGB: Double(swap.xsu_used) / gb)
}

/// Wine으로 실행 중인 game.exe의 CPU%와 메모리(MB). 프로세스 이름으로 찾는다.
final class GameProcessMeter {
    private var lastCPU: UInt64 = 0, lastTime: UInt64 = 0, lastPid: pid_t = 0
    func sample() -> (cpu: Double, memMB: Double)? {
        guard let pid = findPid() else { lastPid = 0; return nil }
        var info = proc_taskinfo()
        guard proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, Int32(MemoryLayout<proc_taskinfo>.size)) > 0 else { return nil }
        let cpuNs = info.pti_total_user + info.pti_total_system
        let now = clock_gettime_nsec_np(CLOCK_MONOTONIC)
        defer { lastCPU = cpuNs; lastTime = now; lastPid = pid }
        var mach = mach_timebase_info_data_t(); mach_timebase_info(&mach)
        let cpuTicksToNs = Double(mach.numer) / Double(mach.denom)
        guard pid == lastPid, now > lastTime else { return (0, Double(info.pti_resident_size) / 1_048_576) }
        let cpu = Double(cpuNs - lastCPU) * cpuTicksToNs / Double(now - lastTime) * 100
        return (cpu, Double(info.pti_resident_size) / 1_048_576)
    }
    private func findPid() -> pid_t? {
        let n = proc_listallpids(nil, 0)
        var pids = [pid_t](repeating: 0, count: Int(n) + 32)
        let got = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        var name = [CChar](repeating: 0, count: 256)
        for pid in pids.prefix(Int(got)) where pid > 0 {
            if proc_name(pid, &name, UInt32(name.count)) > 0, String(cString: name).lowercased() == "game.exe" { return pid }
        }
        return nil
    }
}

/// HID 조이스틱(T10PX 등)의 입력 보고 횟수(Hz)와 X/Y 축 값
final class ControllerMeter {
    private let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    private(set) var deviceName: String?
    private var reports = 0
    private var lastCount = Date()
    private(set) var hz = 0.0
    private(set) var axes: [UInt32: (value: Int, min: Int, max: Int)] = [:]

    init() {
        let match: [[String: Any]] = [
            [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop, kIOHIDDeviceUsageKey: kHIDUsage_GD_Joystick],
            [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop, kIOHIDDeviceUsageKey: kHIDUsage_GD_GamePad],
        ]
        IOHIDManagerSetDeviceMatchingMultiple(manager, match as CFArray)
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { ctx, _, _, device in
            let me = Unmanaged<ControllerMeter>.fromOpaque(ctx!).takeUnretainedValue()
            me.deviceName = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? "조종기"
        }, ctx)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { ctx, _, _, _ in
            let me = Unmanaged<ControllerMeter>.fromOpaque(ctx!).takeUnretainedValue()
            me.deviceName = nil; me.axes = [:]
        }, ctx)
        IOHIDManagerRegisterInputReportCallback(manager, { ctx, _, _, _, _, _, _ in
            Unmanaged<ControllerMeter>.fromOpaque(ctx!).takeUnretainedValue().reports += 1
        }, ctx)
        IOHIDManagerRegisterInputValueCallback(manager, { ctx, _, _, value in
            let me = Unmanaged<ControllerMeter>.fromOpaque(ctx!).takeUnretainedValue()
            let el = IOHIDValueGetElement(value)
            guard IOHIDElementGetUsagePage(el) == UInt32(kHIDPage_GenericDesktop) else { return }
            let usage = IOHIDElementGetUsage(el)
            guard usage == UInt32(kHIDUsage_GD_X) || usage == UInt32(kHIDUsage_GD_Y) else { return }
            me.axes[usage] = (IOHIDValueGetIntegerValue(value), IOHIDElementGetLogicalMin(el), IOHIDElementGetLogicalMax(el))
        }, ctx)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    func tick() {
        let dt = Date().timeIntervalSince(lastCount)
        hz = dt > 0 ? Double(reports) / dt : 0
        reports = 0; lastCount = Date()
    }

    /// -100 ~ +100 (%)
    func percent(_ usage: Int) -> Int? {
        guard let a = axes[UInt32(usage)], a.max > a.min else { return nil }
        let mid = Double(a.max + a.min) / 2, half = Double(a.max - a.min) / 2
        return Int(((Double(a.value) - mid) / half * 100).rounded())
    }
}

// MARK: - 화면

final class Row: NSView {
    let label = NSTextField(labelWithString: "")
    let value = NSTextField(labelWithString: "")
    let bar = NSView()
    private let track = NSView()
    private var fraction: CGFloat = 0

    init(_ title: String, showsBar: Bool = true) {
        super.init(frame: .zero)
        label.stringValue = title
        label.font = .systemFont(ofSize: 11, weight: .regular)
        label.textColor = .secondaryLabelColor
        value.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        value.textColor = .labelColor
        value.alignment = .right
        [label, value].forEach { addSubview($0) }
        if showsBar {
            [track, bar].forEach { $0.wantsLayer = true; $0.layer?.cornerRadius = 1; addSubview($0) }
        }
    }
    required init?(coder: NSCoder) { fatalError() }

    func set(_ text: String, fraction f: Double? = nil) {
        value.stringValue = text
        if let f { fraction = CGFloat(max(0, min(1, f))) }
        needsLayout = true
    }

    override func updateLayer() {}
    override var wantsUpdateLayer: Bool { true }

    override func layout() {
        super.layout()
        let w = bounds.width
        label.frame = NSRect(x: 0, y: 6, width: 90, height: 15)
        value.frame = NSRect(x: 80, y: 6, width: w - 80, height: 16)
        track.frame = NSRect(x: 0, y: 1, width: w, height: 2)
        bar.frame = NSRect(x: 0, y: 1, width: w * fraction, height: 2)
        // 테마가 바뀌어도 시스템 색을 다시 읽도록 매번 지정
        effectiveAppearance.performAsCurrentDrawingAppearance {
            track.layer?.backgroundColor = NSColor.quaternaryLabelColor.cgColor
            bar.layer?.backgroundColor = (fraction > 0.85 ? NSColor.systemOrange : NSColor.secondaryLabelColor).cgColor
        }
    }
    override func viewDidChangeEffectiveAppearance() { needsLayout = true }
}

final class HUDController: NSObject, NSApplicationDelegate {
    private var panel: NSPanel!
    private let cpu = CPUMeter(), game = GameProcessMeter(), pad = ControllerMeter()
    private let rCPU = Row("CPU"), rGPU = Row("GPU"), rMem = Row("메모리"), rSwap = Row("스왑")
    private let rGame = Row("VRC Pro", showsBar: false), rPad = Row("조종기 입력", showsBar: false)
    private let rAxes = Row("스티어링 · 스로틀", showsBar: false)
    private var statusItem: NSStatusItem!
    private var clickThrough = true

    func applicationDidFinishLaunching(_ n: Notification) {
        let width: CGFloat = 228, rowH: CGFloat = 26
        let rows: [NSView] = [rCPU, rGPU, rMem, rSwap, rGame, rPad, rAxes]
        let height = CGFloat(rows.count) * rowH + 30

        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                        styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = clickThrough
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        let bg = NSVisualEffectView(frame: panel.contentView!.bounds)
        bg.material = .hudWindow            // 라이트/다크 모드를 시스템 설정대로 따라감
        bg.blendingMode = .behindWindow
        bg.state = .active
        bg.wantsLayer = true
        bg.layer?.cornerRadius = 8
        bg.layer?.masksToBounds = true
        panel.contentView = bg

        let title = NSTextField(labelWithString: "VRC Pro 모니터")
        title.font = .systemFont(ofSize: 10, weight: .semibold)
        title.textColor = .tertiaryLabelColor
        title.frame = NSRect(x: 16, y: height - 22, width: 160, height: 14)
        bg.addSubview(title)

        for (i, r) in rows.enumerated() {
            // 오른쪽 여백을 살짝 줄여 숫자가 가장자리에 붙어 읽히게
            r.frame = NSRect(x: 16, y: height - 30 - CGFloat(i + 1) * rowH + 2, width: width - 28, height: rowH)
            bg.addSubview(r)
        }
        placeTopRight()
        panel.orderFrontRegardless()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "VRC"
        let menu = NSMenu()
        menu.addItem(withTitle: "모니터 보이기/숨기기", action: #selector(toggleVisible), keyEquivalent: "h").target = self
        menu.addItem(withTitle: "드래그로 위치 옮기기 켜기/끄기", action: #selector(toggleClickThrough), keyEquivalent: "m").target = self
        menu.addItem(withTitle: "오른쪽 위로 되돌리기", action: #selector(resetPosition), keyEquivalent: "r").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu

        _ = cpu.sample()
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in self?.refresh() }
        refresh()
    }

    private func placeTopRight() {
        guard let screen = NSScreen.main else { return }
        let f = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: f.maxX - panel.frame.width - 12, y: f.maxY - panel.frame.height - 10))
    }

    private func refresh() {
        let c = cpu.sample()
        rCPU.set(String(format: "%.0f%%", c), fraction: c / 100)
        let g = gpuUtilization()
        rGPU.set(String(format: "%.0f%%", g), fraction: g / 100)
        let m = memoryInfo()
        rMem.set(String(format: "%.1f / %.0f GB", m.usedGB, m.totalGB), fraction: m.usedGB / m.totalGB)
        rSwap.set(String(format: "%.1f GB", m.swapGB), fraction: m.swapGB / max(m.totalGB / 2, 1))

        if let gp = game.sample() {
            rGame.set(String(format: "CPU %.0f%% · %.0f MB", gp.cpu, gp.memMB))
        } else {
            rGame.set("실행 안 함")
        }

        pad.tick()
        if pad.deviceName != nil {
            rPad.set(String(format: "%.0f Hz", pad.hz))
            let s = pad.percent(kHIDUsage_GD_X).map { String(format: "%+d", $0) } ?? "–"
            let t = pad.percent(kHIDUsage_GD_Y).map { String(format: "%+d", $0) } ?? "–"
            rAxes.set("\(s) · \(t)")
        } else {
            rPad.set("연결 안 됨")
            rAxes.set("–")
        }
    }

    @objc private func toggleVisible() { panel.isVisible ? panel.orderOut(nil) : panel.orderFrontRegardless() }
    @objc private func toggleClickThrough() {
        clickThrough.toggle()
        panel.ignoresMouseEvents = clickThrough
        panel.isMovableByWindowBackground = !clickThrough
    }
    @objc private func resetPosition() { placeTopRight() }
}

let app = NSApplication.shared
let delegate = HUDController()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
