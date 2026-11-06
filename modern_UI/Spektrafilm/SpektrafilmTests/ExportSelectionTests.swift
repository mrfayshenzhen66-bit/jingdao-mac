// ExportSelectionTests.swift — opening policy is separate from recipe contents.
// Every test owns both JSON files; none reads the person's export preferences.

import XCTest

@MainActor
final class ExportSelectionTests: XCTestCase {
    private func withRecipes(_ body: (URL, URL, [ExportRecipe]) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "spk-export-selection-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appending(path: "recipes.json")
        let selectionURL = url.appendingPathExtension("selection.json")
        let recipes = [ExportRecipe(name: "First"), ExportRecipe(name: "mrfay的导出方式")]
        try JSONEncoder().encode(recipes).write(to: url)
        try body(url, selectionURL, recipes)
    }

    func testSelectionIsRememberedWithoutRewritingTheRecipes() throws {
        try withRecipes { url, selectionURL, recipes in
            let bytes = try Data(contentsOf: url)
            let store = ExportRecipeStore(url: url)
            XCTAssertEqual(store.openingBehavior, .lastUsed)
            store.selectedID = recipes[1].id
            XCTAssertTrue(FileManager.default.fileExists(atPath: selectionURL.path))
            XCTAssertEqual(try Data(contentsOf: url), bytes)
            let reopened = ExportRecipeStore(url: url)
            XCTAssertEqual(reopened.selected?.id, recipes[1].id)
            XCTAssertEqual(reopened.recipes, recipes)
        }
    }

    func testFixedDefaultWinsOnOpenButDoesNotReplaceTheLastManualSelection() throws {
        try withRecipes { url, _, recipes in
            let store = ExportRecipeStore(url: url)
            store.selectedID = recipes[1].id
            store.setCurrentAsDefault()
            XCTAssertEqual(store.defaultRecipeID, recipes[1].id)
            XCTAssertEqual(store.openingBehavior, .fixedDefault)
            store.selectedID = recipes[0].id
            XCTAssertEqual(store.selected?.id, recipes[0].id)
            XCTAssertEqual(store.defaultRecipeID, recipes[1].id)
            store.restoreSelection()
            XCTAssertEqual(store.selected?.id, recipes[1].id)
            let reopened = ExportRecipeStore(url: url)
            XCTAssertEqual(reopened.selected?.id, recipes[1].id)
            reopened.openingBehavior = .lastUsed
            reopened.restoreSelection()
            XCTAssertEqual(reopened.selected?.id, recipes[0].id,
                           "Automatic default restoration must not erase the last manual choice")
            XCTAssertNil(reopened.defaultRecipeID)
        }
    }

    func testRenameKeepsTheDefaultIdentityAndDuplicateGetsAnotherIdentity() throws {
        try withRecipes { url, _, recipes in
            let store = ExportRecipeStore(url: url)
            store.selectedID = recipes[1].id
            store.setCurrentAsDefault()
            var renamed = try XCTUnwrap(store.selected)
            renamed.name = "Renamed personal export"
            store.selected = renamed
            store.duplicate(renamed)
            let duplicate = try XCTUnwrap(store.selected)
            XCTAssertNotEqual(duplicate.id, renamed.id)
            XCTAssertEqual(store.defaultRecipeID, renamed.id)
            let reopened = ExportRecipeStore(url: url)
            XCTAssertEqual(reopened.selected?.id, renamed.id)
            XCTAssertEqual(reopened.selected?.name, renamed.name)
            reopened.openingBehavior = .lastUsed
            reopened.restoreSelection()
            XCTAssertEqual(reopened.selected?.id, duplicate.id)
        }
    }

    func testDeletingTheFixedDefaultFallsBackToTheSurvivingLastSelection() throws {
        try withRecipes { url, _, recipes in
            let store = ExportRecipeStore(url: url)
            store.selectedID = recipes[0].id
            store.setCurrentAsDefault()
            store.selectedID = recipes[1].id
            store.restoreSelection()
            store.remove(recipes[0])
            XCTAssertNil(store.defaultRecipeID)
            XCTAssertEqual(store.openingBehavior, .lastUsed)
            XCTAssertEqual(store.selected?.id, recipes[1].id)
            XCTAssertEqual(store.recipes, [recipes[1]])
            let reopened = ExportRecipeStore(url: url)
            XCTAssertEqual(reopened.selected?.id, recipes[1].id)
            XCTAssertNil(reopened.defaultRecipeID)
            reopened.remove(recipes[1])
            XCTAssertEqual(reopened.recipes, [recipes[1]], "The last recipe still cannot be deleted")
        }
    }

    func testMissingPreferenceIdentitiesFallBackToARealRecipe() throws {
        try withRecipes { url, selectionURL, recipes in
            let invalid = ["lastSelectedID": UUID().uuidString, "defaultRecipeID": UUID().uuidString]
            try JSONEncoder().encode(invalid).write(to: selectionURL)
            let store = ExportRecipeStore(url: url)
            XCTAssertEqual(store.selected?.id, recipes[0].id)
            XCTAssertNil(store.defaultRecipeID)
            XCTAssertEqual(store.openingBehavior, .lastUsed)
            store.selectedID = UUID()
            XCTAssertTrue(store.recipes.contains { $0.id == store.selected?.id })
            store.restoreSelection()
            XCTAssertTrue(store.recipes.contains { $0.id == store.selected?.id })
            XCTAssertEqual(store.recipes, recipes)
        }
    }

    func testIndependentRecipeFilesHaveIndependentOpeningPreferences() throws {
        try withRecipes { url, _, recipes in
            let otherURL = url.deletingLastPathComponent().appending(path: "other-recipes.json")
            try JSONEncoder().encode(recipes).write(to: otherURL)
            let first = ExportRecipeStore(url: url)
            first.selectedID = recipes[1].id
            first.setCurrentAsDefault()
            let other = ExportRecipeStore(url: otherURL)
            XCTAssertEqual(other.selected?.id, recipes[0].id)
            XCTAssertNil(other.defaultRecipeID)
            XCTAssertEqual(ExportRecipeStore(url: url).selected?.id, recipes[1].id)
        }
    }

    func testMalformedRecipesAndSelectionFilesAreNotOverwrittenByOpening() throws {
        try withRecipes { url, selectionURL, _ in
            let badRecipes = Data("{ broken recipes".utf8)
            let badSelection = Data("{ broken opening preferences".utf8)
            try badRecipes.write(to: url)
            try badSelection.write(to: selectionURL)
            let store = ExportRecipeStore(url: url)
            XCTAssertNotNil(store.problem)
            XCTAssertNotNil(store.selectionProblem)
            XCTAssertNotNil(store.selected)
            XCTAssertEqual(try Data(contentsOf: url), badRecipes)
            XCTAssertEqual(try Data(contentsOf: selectionURL), badSelection)
        }
    }

    func testLegacyRecipesAcquireStableUniqueIdentitiesBeforeSelectionsAreRemembered() throws {
        try withRecipes { url, _, _ in
            let duplicateID = UUID().uuidString
            let old = """
            [{"name":"Missing identity"},
             {"id":"\(duplicateID)","name":"Original identity"},
             {"id":"\(duplicateID)","name":"Duplicate identity"}]
            """
            try Data(old.utf8).write(to: url)
            let store = ExportRecipeStore(url: url)
            XCTAssertEqual(Set(store.recipes.map(\.id)).count, 3)
            XCTAssertEqual(store.recipes[1].id.uuidString, duplicateID)
            let backups = try FileManager.default.contentsOfDirectory(
                at: url.deletingLastPathComponent(), includingPropertiesForKeys: nil
            ).filter { $0.lastPathComponent.hasPrefix(url.lastPathComponent + ".before-selection-") }
            XCTAssertEqual(backups.count, 1)
            XCTAssertEqual(try Data(contentsOf: XCTUnwrap(backups.first)), Data(old.utf8))
            let chosen = store.recipes[2]
            store.selectedID = chosen.id
            let reopened = ExportRecipeStore(url: url)
            XCTAssertEqual(reopened.recipes.map(\.id), store.recipes.map(\.id))
            XCTAssertEqual(reopened.selected?.id, chosen.id)
            XCTAssertEqual(reopened.selected?.name, chosen.name)
        }
    }

    func testTheCapturedBatchRecipeDoesNotFollowLaterSelectionOrEdits() throws {
        try withRecipes { url, _, recipes in
            let store = ExportRecipeStore(url: url)
            store.selectedID = recipes[1].id
            // ExportPage.run captures this value before its Task and passes
            // that same value to every Exporter.export call in the batch.
            let captured = try XCTUnwrap(store.selected)
            store.selectedID = recipes[0].id
            var next = try XCTUnwrap(store.selected)
            next.name = "Changed while a batch owns its snapshot"
            next.format = .png
            store.selected = next
            store.setCurrentAsDefault()
            XCTAssertEqual(captured, recipes[1])
            XCTAssertEqual(captured.name, "mrfay的导出方式")
            XCTAssertNotEqual(store.selected?.id, captured.id)
        }
    }
}
