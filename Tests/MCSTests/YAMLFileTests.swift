import Foundation
@testable import mcs
import Testing

struct YAMLFileTests {
    private struct Sample: Codable, Equatable {
        let name: String
        let count: Int
    }

    private func makeTmpDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mcs-yamlfile-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Load

    @Test("Load returns nil when file does not exist")
    func loadMissingFile() throws {
        let tmpDir = try makeTmpDir()
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let path = tmpDir.appendingPathComponent("missing.yaml")
        let result = try YAMLFile.load(Sample.self, from: path)
        #expect(result == nil)
    }

    @Test("Load returns nil for empty file")
    func loadEmptyFile() throws {
        let tmpDir = try makeTmpDir()
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let path = tmpDir.appendingPathComponent("empty.yaml")
        try "".write(to: path, atomically: true, encoding: .utf8)

        let result = try YAMLFile.load(Sample.self, from: path)
        #expect(result == nil)
    }

    @Test("Load returns nil for whitespace-only file")
    func loadWhitespaceFile() throws {
        let tmpDir = try makeTmpDir()
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let path = tmpDir.appendingPathComponent("blank.yaml")
        try "   \n  \n  ".write(to: path, atomically: true, encoding: .utf8)

        let result = try YAMLFile.load(Sample.self, from: path)
        #expect(result == nil)
    }

    @Test("Load decodes valid YAML")
    func loadValidYAML() throws {
        let tmpDir = try makeTmpDir()
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let path = tmpDir.appendingPathComponent("valid.yaml")
        try "name: hello\ncount: 42\n".write(to: path, atomically: true, encoding: .utf8)

        let result = try YAMLFile.load(Sample.self, from: path)
        #expect(result == Sample(name: "hello", count: 42))
    }

    @Test("Load throws for corrupt YAML")
    func loadCorruptYAML() throws {
        let tmpDir = try makeTmpDir()
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let path = tmpDir.appendingPathComponent("corrupt.yaml")
        try ":::not:::valid:::yaml:::".write(to: path, atomically: true, encoding: .utf8)

        #expect(throws: (any Error).self) {
            try YAMLFile.load(Sample.self, from: path)
        }
    }

    @Test("Load throws for schema mismatch")
    func loadSchemaMismatch() throws {
        let tmpDir = try makeTmpDir()
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let path = tmpDir.appendingPathComponent("mismatch.yaml")
        try "totally: different\nschema: true\n".write(to: path, atomically: true, encoding: .utf8)

        #expect(throws: (any Error).self) {
            try YAMLFile.load(Sample.self, from: path)
        }
    }

    // MARK: - Save

    @Test("Save creates parent directories")
    func saveCreatesDirectories() throws {
        let tmpDir = try makeTmpDir()
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let path = tmpDir.appendingPathComponent("nested/dir/file.yaml")
        try YAMLFile.save(Sample(name: "test", count: 1), to: path)

        #expect(FileManager.default.fileExists(atPath: path.path))
    }

    @Test("Save and load round-trip preserves data")
    func saveAndLoadRoundTrip() throws {
        let tmpDir = try makeTmpDir()
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let path = tmpDir.appendingPathComponent("roundtrip.yaml")
        let original = Sample(name: "test", count: 99)
        try YAMLFile.save(original, to: path)

        let loaded = try YAMLFile.load(Sample.self, from: path)
        #expect(loaded == original)
    }
}
