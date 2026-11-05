// VRCPro.app — 더블클릭 한 번으로 VRC Pro(Wine)를 실행하는 런처
//  1) 입력 소스를 ABC로 바꾸고  2) VRC HUD를 띄우고  3) 잠자기를 막은 채
//  4) Wine 환경을 직접 넣어 vrcpro.exe를 실행  5) 끝나면 모두 원래대로 되돌린다.
// 빌드: swiftc -O main.swift -o VRCPro -framework Cocoa -framework Carbon -framework IOKit
import Cocoa
import Carbon
import IOKit.pwr_mgt

let home = FileManager.default.homeDirectoryForCurrentUser.path
let engine = "\(home)/Applications/Wine/cx24/wswine.bundle"
let wine = "\(engine)/bin/wine"
let wineserver = "\(engine)/bin/wineserver"
let prefix = "\(home)/Games/VRCPro-cx24"
let gameDir = "\(prefix)/drive_c/Virtual RC Pro"
let hudApp = "\(home)/Applications/VRC HUD.app"
let logFile = "\(home)/Games/VRCPro-last-run.log"

/// Wine이 쓰는 환경 변수. Process로 직접 실행하므로 SIP에 지워지지 않는다.
func wineEnvironment() -> [String: String] {
    var env = ProcessInfo.processInfo.environment
    env["PATH"] = "\(engine)/bin:/usr/bin:/bin"
    env["WINE"] = wine
    env["WINESERVER"] = wineserver
    env["WINEPREFIX"] = prefix
    env["DYLD_FALLBACK_LIBRARY_PATH"] = "\(home)/Applications/Wine/cx24:/usr/lib"
    env["LANG"] = "en_US.UTF-8"
    env["LC_ALL"] = "en_US.UTF-8"
    env["WINEDEBUG"] = "err+all"
    return env
}

// MARK: - 입력 소스

func currentInputSourceID() -> String? {
    guard let src = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
          let ptr = TISGetInputSourceProperty(src, kTISPropertyInputSourceID) else { return nil }
    return Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
}

@discardableResult
func selectInputSource(_ id: String) -> Bool {
    let filter = [kTISPropertyInputSourceID as String: id] as CFDictionary
    guard let list = TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource],
          let src = list.first else { return false }
    return TISSelectInputSource(src) == noErr
}

// MARK: - 앱

final class Launcher: NSObject, NSApplicationDelegate {
    private var savedInputSource: String?
    private var sleepAssertion: IOPMAssertionID = 0
    private var startedHUD = false
    private var quitting = false

    func applicationDidFinishLaunching(_ n: Notification) {
        guard FileManager.default.isExecutableFile(atPath: wine),
              FileManager.default.fileExists(atPath: "\(gameDir)/vrcpro.exe") else {
            alert("VRC Pro를 찾을 수 없어요", "Wine 엔진이나 게임 폴더가 없습니다.\n\(gameDir)")
            NSApp.terminate(nil); return
        }
        if isWineRunning() {
            alert("이미 실행 중이에요", "VRC Pro(Wine)가 이미 켜져 있습니다. Dock에서 게임 창을 찾아보세요.")
            NSApp.terminate(nil); return
        }

        // 1) 입력 소스: 한국어 입력기에서는 Wine이 키보드 배열 전환에 실패하므로 ABC로
        savedInputSource = currentInputSourceID()
        if savedInputSource != "com.apple.keylayout.ABC" { selectInputSource("com.apple.keylayout.ABC") }

        // 2) HUD
        if FileManager.default.fileExists(atPath: hudApp),
           NSRunningApplication.runningApplications(withBundleIdentifier: "io.github.kingpotato1123.vrc-hud").isEmpty {
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: hudApp), configuration: {
                let c = NSWorkspace.OpenConfiguration(); c.activates = false; return c
            }())
            startedHUD = true
        }

        // 3) 잠자기 방지 (화면은 꺼져도 됨)
        IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
                                    IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                    "VRC Pro running" as CFString, &sleepAssertion)

        // 4) 게임 실행 → 끝나면 wineserver가 완전히 내려갈 때까지 기다린 뒤 정리
        DispatchQueue.global().async {
            self.run(wine, ["vrcpro.exe"], cwd: gameDir, log: true)
            self.run(wineserver, ["-w"])
            DispatchQueue.main.async { self.cleanUpAndQuit() }
        }
    }

    /// Dock 아이콘에서 '종료'를 누르면 게임도 정상 절차로 종료
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if quitting { return .terminateNow }
        if isWineRunning() {
            DispatchQueue.global().async {
                self.run(wineserver, ["-k"])
                self.run(wineserver, ["-w"])
                DispatchQueue.main.async { self.cleanUpAndQuit() }
            }
            return .terminateCancel
        }
        cleanUp()
        return .terminateNow
    }

    private func cleanUp() {
        if let id = savedInputSource, id != currentInputSourceID() { selectInputSource(id) }
        savedInputSource = nil
        if sleepAssertion != 0 { IOPMAssertionRelease(sleepAssertion); sleepAssertion = 0 }
        if startedHUD {
            NSRunningApplication.runningApplications(withBundleIdentifier: "io.github.kingpotato1123.vrc-hud").forEach { $0.terminate() }
            startedHUD = false
        }
    }

    private func cleanUpAndQuit() {
        cleanUp()
        quitting = true
        NSApp.terminate(nil)
    }

    private func isWineRunning() -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        p.arguments = ["-f", "\(engine)/.*wineserver"]
        p.standardOutput = FileHandle.nullDevice
        try? p.run(); p.waitUntilExit()
        return p.terminationStatus == 0
    }

    @discardableResult
    private func run(_ path: String, _ args: [String], cwd: String? = nil, log: Bool = false) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        p.environment = wineEnvironment()
        if let cwd { p.currentDirectoryURL = URL(fileURLWithPath: cwd) }
        if log {
            FileManager.default.createFile(atPath: logFile, contents: nil)
            let h = FileHandle(forWritingAtPath: logFile)
            p.standardOutput = h; p.standardError = h
        } else {
            p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        }
        do { try p.run() } catch { return -1 }
        p.waitUntilExit()
        return p.terminationStatus
    }

    private func alert(_ title: String, _ text: String) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        a.runModal()
    }
}

let app = NSApplication.shared
let delegate = Launcher()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
