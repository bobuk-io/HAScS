import BobukTestSupport
import Foundation
import Testing
@testable import BobukCore

@Suite struct KeyboardLayoutSwapTests {
    @Test func variantsInTingOrder() {
        #expect(KeyboardLayoutSwap.variants(of: "Safari").first == "safari")
        #expect(KeyboardLayoutSwap.variants(of: "ыф") == ["ыф", "sa"])
        #expect(KeyboardLayoutSwap.variants(of: "sa") == ["sa", "ыф", "іф"])
        #expect(KeyboardLayoutSwap.variants(of: "ta") == ["ta", "еф"])
        #expect(KeyboardLayoutSwap.variants(of: "123") == ["123"])
    }

    @Test func physicalKeysAsInLowkey() {
        #expect(KeyboardLayoutSwap.variants(of: "РФ").contains("ha"))
        #expect(KeyboardLayoutSwap.variants(of: "пщщпду").contains("google"))
        #expect(KeyboardLayoutSwap.variants(of: "шї").contains("i]"))
        #expect(KeyboardLayoutSwap.variants(of: "і").contains("s"))
        #expect(KeyboardLayoutSwap.variants(of: "ntktuhfv").contains("телеграм"))
        #expect(KeyboardLayoutSwap.variants(of: "").count == 1)
    }
}

@Suite struct AppPathsTests {
    private let home = URL(fileURLWithPath: "/Users/demo")

    @Test func defaultLocations() {
        let ting = AppPaths(supportFolder: "Ting", configFolder: "ting", overrideVariable: "TING_CONFIG", environment: [:], home: home)
        #expect(ting.config.path == "/Users/demo/.config/ting/config.json")
        #expect(ting.file("history.json").path == "/Users/demo/Library/Application Support/Ting/history.json")
        #expect(!ting.isIsolated)
        let lowkey = AppPaths(supportFolder: "Lowkey", overrideVariable: "LOWKEY_CONFIG", environment: [:], home: home)
        #expect(lowkey.config.path == "/Users/demo/Library/Application Support/Lowkey/config.json")
        #expect(lowkey.companion(".history.json").path == "/Users/demo/Library/Application Support/Lowkey/config.json.history.json")
    }

    @Test func overrideMovesEveryFile() {
        let paths = AppPaths(supportFolder: "Ting", configFolder: "ting", overrideVariable: "TING_CONFIG",
                             environment: ["TING_CONFIG": "/tmp/x/test.json"], home: home)
        #expect(paths.isIsolated)
        #expect(paths.config.path == "/tmp/x/test.json")
        #expect(paths.file("history.json").path == "/tmp/x/history.json")
        #expect(paths.companion(".history.json").path == "/tmp/x/test.json.history.json")
        #expect(paths.dataFile("launcha-history.json").path == "/tmp/x/test.json.launcha-history.json")
        let plain = AppPaths(supportFolder: "Ting", environment: [:], home: home)
        #expect(plain.dataFile("launcha-history.json").path == "/Users/demo/Library/Application Support/Ting/launcha-history.json")
        let folder = AppPaths(supportFolder: "Splash Finish", configFileName: "state.json", folderOverrideVariable: "SPLASH_FINISH_HOME",
                              environment: ["SPLASH_FINISH_HOME": "/tmp/splash"], home: home)
        #expect(folder.support.path == "/tmp/splash")
        #expect(folder.config.path == "/tmp/splash/state.json")
        #expect(folder.file("app.lock").path == "/tmp/splash/app.lock")
        let empty = AppPaths(supportFolder: "Ting", overrideVariable: "TING_CONFIG", environment: ["TING_CONFIG": ""], home: home)
        #expect(!empty.isIsolated)
    }
}

@Suite(.serialized) struct SafeFileTests {
    @Test func writesAtomicallyAndKeepsPermissions() throws {
        let folder = try TemporaryDirectory()
        let file = folder.url.appendingPathComponent("nested/data.json")
        try SafeFile.write(Data("one".utf8), to: file)
        let mode = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber
        #expect(mode?.intValue == 0o600)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)
        try SafeFile.write(Data("two".utf8), to: file)
        #expect(try String(contentsOf: file, encoding: .utf8) == "two")
        let kept = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber
        #expect(kept?.intValue == 0o644)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: file.deletingLastPathComponent().path)
        #expect(leftovers == ["data.json"])
    }

    @Test func refusesSymlinks() throws {
        let folder = try TemporaryDirectory()
        let target = folder.url.appendingPathComponent("target")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let link = folder.url.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        #expect(throws: SafeFileError.self) { try SafeFile.write(Data(), to: link.appendingPathComponent("x")) }
    }

    @Test func lockIsExclusive() throws {
        let folder = try TemporaryDirectory()
        let url = folder.url.appendingPathComponent("app.lock")
        var first: FileLock? = try FileLock(url: url, nonblocking: true)
        #expect(throws: SafeFileError.self) { _ = try FileLock(url: url, nonblocking: true, busyMessage: "busy") }
        first = nil
        _ = first
        _ = try FileLock(url: url, nonblocking: true)
    }
}

@Suite(.serialized) struct JSONFileStoreTests {
    struct Settings: Codable, Equatable, Sendable { var name = "default" }

    @Test func missingLoadedAndSaved() throws {
        let folder = try TemporaryDirectory()
        let store = JSONFileStore<Settings>(url: folder.url.appendingPathComponent("settings.json")) { Settings() }
        guard case .missing(let value) = store.load() else { Issue.record("expected missing"); return }
        #expect(value == Settings())
        try store.save(Settings(name: "saved"))
        #expect(store.load().value == Settings(name: "saved"))
    }

    @Test func refusesToOverwriteAnUnreadableFile() throws {
        let folder = try TemporaryDirectory()
        let url = folder.url.appendingPathComponent("settings.json")
        try Data("{broken".utf8).write(to: url)
        let store = JSONFileStore<Settings>(url: url) { Settings() }
        #expect(store.load().value == nil)
        #expect(throws: JSONFileStoreError.self) { try store.save(Settings(name: "x")) }
        #expect(try String(contentsOf: url, encoding: .utf8) == "{broken")
    }

    @Test func backsUpAnUnreadableFile() throws {
        let folder = try TemporaryDirectory()
        let url = folder.url.appendingPathComponent("history.json")
        try Data("{broken".utf8).write(to: url)
        let store = JSONFileStore<Settings>(url: url, policy: .backUp) { Settings() }
        guard case .recovered(let value, let backup) = store.load() else { Issue.record("expected recovery"); return }
        #expect(value == Settings())
        #expect(try String(contentsOf: backup, encoding: .utf8) == "{broken")
        try store.save(Settings(name: "fresh"))
        #expect(store.load().value == Settings(name: "fresh"))
    }
}

@Suite struct RecentListTests {
    @Test func mostRecentFirstCaseInsensitiveWithLimit() {
        var list = RecentList(limit: 3)
        for entry in ["a", "b", "c", "A", "  ", "d"] { list.record(entry) }
        #expect(list.entries == ["d", "A", "c"])
        list.remove("a")
        #expect(list.entries == ["d", "c"])
        #expect(list.contains("D"))
        let decoded = try? JSONDecoder().decode(RecentList.self, from: Data(#"{"entries":["x","X","y"]}"#.utf8))
        #expect(decoded?.entries == ["x", "y"])
    }
}

@Suite struct PanelPlacementTests {
    private let area = CGRect(x: 0, y: 0, width: 1000, height: 800)
    private let size = CGSize(width: 400, height: 200)

    @Test func anchors() {
        #expect(PanelPlacement.frame(size: size, in: area, anchor: .center()) == CGRect(x: 300, y: 300, width: 400, height: 200))
        // launcha: top edge max(40, 16 %) below the top.
        #expect(abs(PanelPlacement.frame(size: size, in: area, anchor: .upper()).maxY - 672) < 0.001)
        #expect(abs(PanelPlacement.top(in: area, anchor: .upper()) - 672) < 0.001)
        #expect(PanelPlacement.frame(size: size, in: area, anchor: .top(inset: 80)).maxY == 720)
        // Splash Finish: 55 points below the center.
        #expect(PanelPlacement.frame(size: size, in: area, anchor: .center(offsetUp: -55)).minY == 245)
        // A panel taller than the screen keeps its top on screen.
        let tall = PanelPlacement.frame(size: CGSize(width: 400, height: 900), in: area, anchor: .center())
        #expect(tall.minY == 16)
    }

    @Test func rememberedCornerIsClampedOrIgnored() {
        let screens = [area, CGRect(x: 1000, y: 0, width: 800, height: 600)]
        let kept = PanelPlacement.place(size: size, remembered: CGPoint(x: 1700, y: 590), screens: screens, active: area)
        #expect(kept.frame == CGRect(x: 1400, y: 390, width: 400, height: 200))
        #expect(kept.area == screens[1])
        let gone = PanelPlacement.place(size: size, remembered: CGPoint(x: 5000, y: 5000), screens: screens, active: area)
        #expect(gone.frame.minY == 245)
    }

    @Test func resizeKeepsTheTopEdge() {
        let frame = CGRect(x: 10, y: 400, width: 300, height: 200)
        #expect(PanelPlacement.resize(frame, toHeight: 100).maxY == 600)
        #expect(PanelPlacement.over(parent: CGRect(x: 0, y: 0, width: 800, height: 600), size: size, inset: 56)
            == CGRect(x: 200, y: 344, width: 400, height: 200))
    }
}

@Suite struct ChildProcessTests {
    @Test func collectsOutputAndExitCode() async {
        let request = ChildProcessRequest(executable: "/bin/sh", arguments: ["-c", "cat; echo err >&2; exit 3"],
                                          stdin: Data("hello".utf8), timeLimit: 5)
        let outcome = await ChildProcess.run(request)
        #expect(outcome.end == .exited(3))
        #expect(outcome.stdoutText == "hello")
        #expect(outcome.stderrText == "err\n")
    }

    @Test func timeLimitStopsTheGroupAndOutputIsCut() async {
        let slow = await ChildProcess.run(ChildProcessRequest(executable: "/bin/sleep", arguments: ["5"], timeLimit: 0.2))
        #expect(slow.end == .timedOut)
        let loud = await ChildProcess.run(ChildProcessRequest(executable: "/bin/sh", arguments: ["-c", "yes | head -c 5000"],
                                                              timeLimit: 5, outputLimit: 100))
        #expect(loud.stdout.count == 100)
        #expect(loud.stdoutCut)
        let missing = await ChildProcess.run(ChildProcessRequest(executable: "/nonexistent", timeLimit: 1))
        guard case .notStarted = missing.end else { Issue.record("expected notStarted"); return }
    }
}

@Suite struct MessagePortTests {
    @Test func roundTrip() {
        let name = MessagePortServer.name(prefix: "io.bobuk.bobukkit-test.\(UUID().uuidString)")
        let server = MessagePortServer(name: name) { _, payload in Data(("echo:" + String(decoding: payload, as: UTF8.self)).utf8) }
        #expect(server != nil)
        #expect(MessagePortClient.isListening(name))
        let reply = MessagePortClient.send(Data("ping".utf8), to: name, timeout: 2)
        #expect((try? reply.get()).map { String(decoding: $0, as: UTF8.self) } == "echo:ping")
        #expect(MessagePortClient.send(Data(), to: name + ".missing", timeout: 0.2) == .failure(.notListening))
        withExtendedLifetime(server) {}
    }
}

@Suite struct AppBundleTests {
    @Test func applicationURLOnlyForBundles() {
        let inside = URL(fileURLWithPath: "/Applications/Splash Finish.app/Contents/MacOS/SplashFinish")
        #expect(AppBundle.applicationURL(for: inside)?.path == "/Applications/Splash Finish.app")
        #expect(AppBundle.applicationURL(for: URL(fileURLWithPath: "/usr/local/bin/tool")) == nil)
        #expect(AppBundle.isProcessSerialNumber("-psn_0_1234"))
        #expect(AppBundle.hasSparkleFeed(info: ["SUFeedURL": "https://x", "SUPublicEDKey": "k"]))
        #expect(!AppBundle.hasSparkleFeed(info: ["SUFeedURL": "https://x"]))
    }

    @Test func virtualKeys() {
        #expect(VirtualKey.digit(18) == 1 && VirtualKey.digit(29) == 0 && VirtualKey.digit(92) == 9)
        #expect(VirtualKey.isReturn(36) && VirtualKey.isReturn(76) && !VirtualKey.isReturn(53))
    }
}
