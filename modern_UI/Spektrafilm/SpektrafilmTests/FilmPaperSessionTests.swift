// FilmPaperSessionTests.swift — exercise the actual Session entry points. A
// remembered starting pair must never replace a photograph's saved decisions.

import XCTest

@MainActor
final class FilmPaperSessionTests: XCTestCase {
    private func withSession(_ body: (Session, UserDefaults, [URL]) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "spk-pair-session-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let suite = "spk-pair-session-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let previousStore = Sidecar.storeDirectory
        Sidecar.useStore(at: root.appending(path: "Sidecars"))
        defer {
            Sidecar.useStore(at: previousStore)
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        let diagnostics = Diagnostics(defaults: defaults)
        let renderer = try XCTUnwrap(Renderer(arena: diagnostics.arena))
        let cache = try DiskCacheStore(root: root.appending(path: "Cache"))
        let session = Session(renderer: renderer, diagnostics: diagnostics, diskCache: cache,
                              clipboardDefaults: defaults, filmPaperDefaults: defaults)
        let files = (0..<3).map { root.appending(path: "photo-\($0).png") }
        for url in files { try Data().write(to: url) }
        session.open(urls: files)
        // These tests inspect the synchronous selection/edit boundary; no
        // decoder task needs to run or fabricate a photograph's pixels.
        defer {
            session.batchExporting = false
            session.flushSave()
            if let url = session.selection { session.remove(url) }
        }
        XCTAssertFalse(session.catalog.stocks.isEmpty, "The test bundle must contain its stock catalogue")
        try body(session, defaults, session.frames.map(\.id))
    }

    private func differentCombination(in session: Session) throws -> FilmPaperCombination {
        var next = FilmParams()
        let film = try XCTUnwrap(session.catalog.films.first {
            !$0.isPositive && !$0.isMonochrome && $0.id != next.filmStock
        })
        next.filmStock = film.id
        if let paper = film.targetPrint { next.printStock = paper }
        return try XCTUnwrap(FilmPaperCombination(next).validated(in: session.catalog))
    }

    func testSavedProcessedAndUnprocessedEditsBeatTheRememberedStartingPair() throws {
        try withSession { session, _, _ in
            let next = try differentCombination(in: session)
            XCTAssertTrue(session.applyFilmPaperCombination(next))
            XCTAssertEqual(FilmPaperCombination(session.startingSidecar(saved: nil).params), next)
            var old = Sidecar()
            old.params.exposureCompensationEV = -1.7
            old.adjustments.saturation = 19
            old.decode.temperature = 4200
            for state: FrameState in [.unprocessed, .processed, .stale] {
                old.state = state
                XCTAssertEqual(session.startingSidecar(saved: old), old)
                XCTAssertEqual(session.filmPaperPresets.lastCombination, next)
            }
            session.filmPaperPresets.rememberLastCombination = false
            XCTAssertEqual(session.startingSidecar(saved: nil).params, FilmParams())
            XCTAssertEqual(session.filmPaperPresets.lastCombination, next)
        }
    }

    func testApplyingACombinationPreservesEveryOtherPhotographicSettingAndRejectsBadInput() throws {
        try withSession { session, defaults, _ in
            var own = Sidecar()
            own.params.exposureCompensationEV = -1.2
            own.params.printBrightnessStops = 0.6
            own.params.yFilterShift = 0.2
            own.params.mFilterShift = -0.3
            own.params.grainActive = false
            own.decode.temperature = 4300
            own.adjustments.saturation = 23
            session.sidecar = own
            let next = try differentCombination(in: session)
            XCTAssertTrue(session.applyFilmPaperCombination(next))
            // The normal edit path derives the film-edge stock name and date
            // metadata. Those describe the chosen material, not copied edits.
            XCTAssertEqual(session.params, session.resolved(next.applied(to: own.params)))
            XCTAssertEqual(session.params.exposureCompensationEV, own.params.exposureCompensationEV)
            XCTAssertEqual(session.params.printBrightnessStops, own.params.printBrightnessStops)
            XCTAssertEqual(session.params.yFilterShift, own.params.yFilterShift)
            XCTAssertEqual(session.params.mFilterShift, own.params.mFilterShift)
            XCTAssertEqual(session.decode, own.decode)
            XCTAssertEqual(session.adjustments, own.adjustments)
            XCTAssertEqual(session.geometry, own.geometry)
            XCTAssertEqual(FilmPaperPresetStore(defaults: defaults).lastCombination, next)

            var invalid = next
            invalid.filmStock = "missing-preset-film"
            let before = session.sidecar
            XCTAssertFalse(session.applyFilmPaperCombination(invalid))
            XCTAssertEqual(session.sidecar, before)
            XCTAssertEqual(session.filmPaperPresets.lastCombination, next)
        }
    }

    func testBrowsingOldFramesDoesNotChangeMemoryAndNewFramesPinTheirInitialPair() throws {
        try withSession { session, _, files in
            let remembered = try differentCombination(in: session)
            XCTAssertTrue(session.applyFilmPaperCombination(remembered))
            var old = Sidecar()
            old.state = .processed
            old.params.exposureCompensationEV = -1.1
            try old.save(for: files[0])
            session.select(files[0])
            XCTAssertEqual(FilmPaperCombination(session.params), FilmPaperCombination(old.params))
            XCTAssertEqual(session.filmPaperPresets.lastCombination, remembered)

            session.select(files[1])
            XCTAssertEqual(FilmPaperCombination(session.params), remembered)
            session.flushSave()
            XCTAssertEqual(FilmPaperCombination(try XCTUnwrap(Sidecar.load(for: files[1])).params), remembered)
            session.select(files[2])
            XCTAssertTrue(session.applyFilmPaperCombination(FilmPaperCombination(FilmParams())))
            session.select(files[1])
            XCTAssertEqual(FilmPaperCombination(session.params), remembered)
            session.select(files[0])
            XCTAssertEqual(session.params.exposureCompensationEV, old.params.exposureCompensationEV)
            XCTAssertEqual(FilmPaperCombination(session.params), FilmPaperCombination(old.params))
        }
    }

    func testUnrelatedEditsAndBatchTraversalCannotReplaceTheRememberedPair() throws {
        try withSession { session, _, files in
            let remembered = try differentCombination(in: session)
            XCTAssertTrue(session.applyFilmPaperCombination(remembered))
            var old = Sidecar()
            old.state = .unprocessed
            try old.save(for: files[0])
            session.select(files[0])
            var changed = session.params
            changed.exposureCompensationEV = 1.5
            session.params = changed
            XCTAssertEqual(session.filmPaperPresets.lastCombination, remembered)

            session.batchExporting = true
            let before = session.sidecar
            XCTAssertFalse(session.canApplyFilmPaperCombination)
            XCTAssertFalse(session.applyFilmPaperCombination(remembered))
            XCTAssertEqual(session.sidecar, before)
            session.select(files[1]) // the exporter's internal door, not a click
            XCTAssertEqual(FilmPaperCombination(session.params), remembered)
            session.select(files[0])
            XCTAssertEqual(session.filmPaperPresets.lastCombination, remembered)
            session.batchExporting = false
        }
    }
}
