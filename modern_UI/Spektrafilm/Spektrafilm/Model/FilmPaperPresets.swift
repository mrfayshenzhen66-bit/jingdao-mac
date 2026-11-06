// FilmPaperPresets.swift — a starting material pair for new photographs, and
// named pairs the person can recall. Neither is a second home for frame edits.

import Foundation
import Observation

struct FilmPaperCombination: Codable, Equatable, Sendable {
    var filmStock: String
    var printStock: String
    var scanFilm: Bool
    var digitalIntermediate: Bool
    var extendedDynamicRange: Bool

    init(_ params: FilmParams) {
        filmStock = params.filmStock
        printStock = params.printStock
        scanFilm = params.scanFilm
        digitalIntermediate = params.digitalIntermediate
        extendedDynamicRange = params.extendedDynamicRange
    }

    /// Apply only material/output choices. Exposure, filters, grain, placement
    /// and every other photographic decision remain the target's own.
    func applied(to params: FilmParams) -> FilmParams {
        var result = params
        result.filmStock = filmStock
        result.printStock = printStock
        result.scanFilm = scanFilm
        result.digitalIntermediate = digitalIntermediate
        result.extendedDynamicRange = extendedDynamicRange
        return result
    }

    /// A remembered id can outlive a catalogue entry. Do not let the engine
    /// silently substitute another material, or pair silver film with colour
    /// paper. A slide is already positive and follows the picker's scan path.
    func validated(in catalog: StockCatalog) -> FilmPaperCombination? {
        guard let film = catalog.stock(filmStock), film.isFilm,
              let paper = catalog.stock(printStock), paper.isPaper,
              catalog.canPrint(film: filmStock, on: printStock) else { return nil }
        var result = self
        if film.isPositive { result.scanFilm = true }
        return result
    }
}

struct FilmPaperPreset: Codable, Equatable, Sendable, Identifiable {
    var id = UUID()
    var name: String
    var combination: FilmPaperCombination
}

enum FilmPaperPresetError: LocalizedError {
    case emptyName
    case duplicateName
    case presetNotFound

    var errorDescription: String? {
        switch self {
        case .emptyName: "Enter a name for the combination preset."
        case .duplicateName: "A combination preset already has that name. Choose another name."
        case .presetNotFound: "That combination preset no longer exists."
        }
    }
}

@MainActor
@Observable
final class FilmPaperPresetStore {
    private enum Key {
        static let remember = "ui2.filmPaper.rememberLastCombination"
        static let last = "ui2.filmPaper.lastCombination.v1"
        static let presets = "ui2.filmPaper.presets.v1"
    }

    @ObservationIgnored private let defaults: UserDefaults

    var rememberLastCombination: Bool {
        didSet {
            if oldValue != rememberLastCombination {
                defaults.set(rememberLastCombination, forKey: Key.remember)
            }
        }
    }
    private(set) var lastCombination: FilmPaperCombination?
    private(set) var presets: [FilmPaperPreset]
    /// A malformed stored payload is left in place and reported, not silently
    /// replaced merely because the app was opened.
    private(set) var problem: String?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        rememberLastCombination = defaults.object(forKey: Key.remember) == nil
            ? true : defaults.bool(forKey: Key.remember)
        lastCombination = nil
        presets = []
        var problems: [String] = []
        if let data = defaults.data(forKey: Key.last) {
            do { lastCombination = try JSONDecoder().decode(FilmPaperCombination.self, from: data) }
            catch { problems.append("The last film and paper combination could not be read.") }
        }
        if let data = defaults.data(forKey: Key.presets) {
            do { presets = try JSONDecoder().decode([FilmPaperPreset].self, from: data) }
            catch { problems.append("The film and paper presets could not be read.") }
        }
        problem = problems.isEmpty ? nil : problems.joined(separator: " ")
    }

    /// Turning memory off leaves the last saved choice intact, but neither
    /// follows subsequent edits nor prevents explicit named presets being saved.
    func remember(_ combination: FilmPaperCombination) {
        guard rememberLastCombination, combination != lastCombination else { return }
        do {
            let data = try JSONEncoder().encode(combination)
            defaults.set(data, forKey: Key.last)
            lastCombination = combination
        } catch {
            problem = "The last film and paper combination could not be saved: \(error.localizedDescription)"
        }
    }

    @discardableResult
    func savePreset(name: String, combination: FilmPaperCombination) throws -> FilmPaperPreset {
        let name = try checkedName(name)
        let preset = FilmPaperPreset(name: name, combination: combination)
        try persist(presets + [preset])
        return preset
    }

    func renamePreset(id: UUID, name: String) throws {
        guard let index = presets.firstIndex(where: { $0.id == id }) else {
            throw FilmPaperPresetError.presetNotFound
        }
        let name = try checkedName(name, excluding: id)
        var next = presets
        next[index].name = name
        try persist(next)
    }

    func deletePreset(id: UUID) {
        guard presets.contains(where: { $0.id == id }) else { return }
        do { try persist(presets.filter { $0.id != id }) }
        catch { problem = "The film and paper preset could not be deleted: \(error.localizedDescription)" }
    }

    private func checkedName(_ raw: String, excluding id: UUID? = nil) throws -> String {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw FilmPaperPresetError.emptyName }
        guard !presets.contains(where: {
            $0.id != id && $0.name.compare(name, options: .caseInsensitive,
                                           locale: Locale(identifier: "en_US_POSIX")) == .orderedSame
        }) else { throw FilmPaperPresetError.duplicateName }
        return name
    }

    private func persist(_ next: [FilmPaperPreset]) throws {
        // Encode before replacing the live list so an error cannot leave the
        // UI claiming a preset was saved while the stored list is still old.
        let data = try JSONEncoder().encode(next)
        defaults.set(data, forKey: Key.presets)
        presets = next
    }
}
