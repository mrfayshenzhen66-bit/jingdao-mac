// FilmPaperPresetsTests.swift — the remembered starting point is not a frame's
// edit, and a named combination must never carry another photograph's exposure.

import XCTest

@MainActor
final class FilmPaperPresetsTests: XCTestCase {
    private func defaults() throws -> UserDefaults {
        let name = "spk-film-paper-presets-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }

    private func stock(_ id: String, stage: String, positive: Bool = false,
                       monochrome: Bool = false) -> Stock {
        Stock(id: id, name: id, stage: stage, use: "still",
              type: stage == "filming" ? (positive ? "positive" : "negative") : nil,
              targetPrint: nil, hasPreviewLUT: false, pairedFilm: nil,
              cover: nil, formats: nil, monochrome: monochrome,
              noAntihalationLayer: nil)
    }

    private var catalog: StockCatalog {
        StockCatalog(stocks: [
            stock("colour", stage: "filming"),
            stock("slide", stage: "filming", positive: true),
            stock("silver", stage: "filming", monochrome: true),
            stock("paper", stage: "printing"),
            stock("silver-paper", stage: "printing", monochrome: true),
        ])
    }

    private func combination(film: String = "colour", paper: String = "paper") -> FilmPaperCombination {
        var params = FilmParams()
        params.filmStock = film
        params.printStock = paper
        return FilmPaperCombination(params)
    }

    func testOnlyTheCombinationIsAppliedToAnotherPhotograph() {
        var source = FilmParams()
        source.filmStock = "slide"
        source.printStock = "paper"
        source.scanFilm = true
        source.digitalIntermediate = true
        source.extendedDynamicRange = true
        source.exposureCompensationEV = 5
        source.yFilterShift = 0.8

        var target = FilmParams()
        target.exposureCompensationEV = -1.5
        target.printBrightnessStops = 0.7
        target.yFilterShift = -0.2
        target.mFilterShift = 0.3
        target.grainActive = false
        target.autoExposure = false
        var expected = target
        expected.filmStock = "slide"
        expected.printStock = "paper"
        expected.scanFilm = true
        expected.digitalIntermediate = true
        expected.extendedDynamicRange = true

        XCTAssertEqual(FilmPaperCombination(source).applied(to: target), expected)
    }

    func testValidationRejectsMissingStocksWrongStagesAndIncompatiblePaper() {
        XCTAssertNil(combination(film: "missing").validated(in: catalog))
        XCTAssertNil(combination(paper: "missing").validated(in: catalog))
        XCTAssertNil(combination(film: "paper").validated(in: catalog))
        XCTAssertNil(combination(paper: "colour").validated(in: catalog))
        XCTAssertNil(combination(film: "silver").validated(in: catalog))
        XCTAssertNil(combination(paper: "silver-paper").validated(in: catalog))
        let silver = combination(film: "silver", paper: "silver-paper")
        XCTAssertEqual(silver.validated(in: catalog), silver)
    }

    func testSlideValidationSelectsFilmScanningWithoutChangingOtherPreferences() throws {
        var slide = combination(film: "slide")
        slide.digitalIntermediate = true
        slide.extendedDynamicRange = true
        let validated = try XCTUnwrap(slide.validated(in: catalog))
        XCTAssertTrue(validated.scanFilm)
        var expected = slide
        expected.scanFilm = true
        XCTAssertEqual(validated, expected)
        var negativeScan = combination()
        negativeScan.scanFilm = true
        XCTAssertEqual(negativeScan.validated(in: catalog), negativeScan)
    }

    func testRememberedCombinationAndNamedPresetsSurviveAStoreReopen() throws {
        let defaults = try defaults()
        let first = FilmPaperPresetStore(defaults: defaults)
        XCTAssertTrue(first.rememberLastCombination)
        XCTAssertNil(first.lastCombination)
        let value = combination()
        first.remember(value)
        let preset = try first.savePreset(name: "  海边日落  ", combination: value)

        let reopened = FilmPaperPresetStore(defaults: defaults)
        XCTAssertEqual(reopened.lastCombination, value)
        XCTAssertEqual(reopened.presets, [preset])
        XCTAssertEqual(reopened.presets.first?.name, "海边日落")
        XCTAssertTrue(reopened.rememberLastCombination)
    }

    func testDisablingRememberPersistsAndDoesNotChangeTheSavedStartingPoint() throws {
        let defaults = try defaults()
        let store = FilmPaperPresetStore(defaults: defaults)
        let old = combination()
        store.remember(old)
        store.rememberLastCombination = false
        let next = combination(film: "slide")
        store.remember(next)
        _ = try store.savePreset(name: "正片", combination: next)

        let reopened = FilmPaperPresetStore(defaults: defaults)
        XCTAssertFalse(reopened.rememberLastCombination)
        XCTAssertEqual(reopened.lastCombination, old)
        XCTAssertEqual(reopened.presets.count, 1)
        reopened.rememberLastCombination = true
        reopened.remember(next)
        XCTAssertEqual(FilmPaperPresetStore(defaults: defaults).lastCombination, next)
    }

    func testRenameAndDeletePersistWithoutChangingTheLastCombination() throws {
        let defaults = try defaults()
        let store = FilmPaperPresetStore(defaults: defaults)
        let value = combination()
        store.remember(value)
        let first = try store.savePreset(name: "First", combination: value)
        let second = try store.savePreset(name: "Second", combination: combination(film: "slide"))
        try store.renamePreset(id: first.id, name: "  海边  ")
        store.deletePreset(id: second.id)

        let reopened = FilmPaperPresetStore(defaults: defaults)
        XCTAssertEqual(reopened.presets.map(\.name), ["海边"])
        XCTAssertEqual(reopened.presets.first?.id, first.id)
        XCTAssertEqual(reopened.lastCombination, value)
        reopened.deletePreset(id: first.id)
        XCTAssertTrue(FilmPaperPresetStore(defaults: defaults).presets.isEmpty)
        XCTAssertEqual(FilmPaperPresetStore(defaults: defaults).lastCombination, value)
    }

    func testEmptyAndDuplicateNamesCannotSilentlyReplaceAPreset() throws {
        let defaults = try defaults()
        let store = FilmPaperPresetStore(defaults: defaults)
        let first = try store.savePreset(name: "Sunset", combination: combination())
        let second = try store.savePreset(name: "Slide", combination: combination(film: "slide"))
        XCTAssertThrowsError(try store.savePreset(name: " \n\t", combination: combination()))
        XCTAssertThrowsError(try store.savePreset(name: " sunset ", combination: combination(film: "slide")))
        XCTAssertThrowsError(try store.renamePreset(id: second.id, name: "SUNSET"))
        XCTAssertThrowsError(try store.renamePreset(id: first.id, name: " \n"))
        XCTAssertThrowsError(try store.renamePreset(id: UUID(), name: "Missing"))
        try store.renamePreset(id: first.id, name: " Sunset ")
        XCTAssertEqual(FilmPaperPresetStore(defaults: defaults).presets, [first, second])
    }

    func testSeparateDefaultsSuitesNeverShareCombinationsOrPresets() throws {
        let one = FilmPaperPresetStore(defaults: try defaults())
        let two = FilmPaperPresetStore(defaults: try defaults())
        one.remember(combination())
        _ = try one.savePreset(name: "Private to this suite", combination: combination())
        one.rememberLastCombination = false
        XCTAssertNil(two.lastCombination)
        XCTAssertTrue(two.presets.isEmpty)
        XCTAssertTrue(two.rememberLastCombination)
    }
}
