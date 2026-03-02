import Foundation
import Testing

@testable import mcs

@Suite("PackFetcher ref validation")
struct PackFetcherRefValidationTests {

    private func makeFetcher() -> PackFetcher {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mcs-fetcher-test-\(UUID().uuidString)")
        let env = Environment(home: tmpDir)
        return PackFetcher(
            shell: ShellRunner(environment: env),
            output: CLIOutput(colorsEnabled: false),
            packsDirectory: tmpDir
        )
    }

    // MARK: - Valid refs

    @Test("Accepts valid semver tag")
    func acceptsSemverTag() throws {
        try makeFetcher().validateRef("v1.0.0")
    }

    @Test("Accepts simple branch name")
    func acceptsSimpleBranch() throws {
        try makeFetcher().validateRef("main")
    }

    @Test("Accepts branch with slash")
    func acceptsBranchWithSlash() throws {
        try makeFetcher().validateRef("feature/my-feature")
    }

    @Test("Accepts dotted pre-release tag")
    func acceptsDottedTag() throws {
        try makeFetcher().validateRef("v1.0.0-rc.1")
    }

    @Test("Accepts ref with plus")
    func acceptsRefWithPlus() throws {
        try makeFetcher().validateRef("v1+build")
    }

    @Test("Accepts commit-like hex prefix")
    func acceptsCommitPrefix() throws {
        try makeFetcher().validateRef("abc123def")
    }

    // MARK: - Rejected refs

    @Test("Rejects double-dash flag injection")
    func rejectsDoubleDashFlag() throws {
        #expect(throws: PackFetchError.self) {
            try makeFetcher().validateRef("--upload-pack=evil")
        }
    }

    @Test("Rejects single-dash flag")
    func rejectsSingleDashFlag() throws {
        #expect(throws: PackFetchError.self) {
            try makeFetcher().validateRef("-b")
        }
    }

    @Test("Rejects path traversal with ..")
    func rejectsPathTraversal() throws {
        #expect(throws: PackFetchError.self) {
            try makeFetcher().validateRef("v1/../../../etc/passwd")
        }
    }

    @Test("Rejects spaces")
    func rejectsSpaces() throws {
        #expect(throws: PackFetchError.self) {
            try makeFetcher().validateRef("main branch")
        }
    }

    @Test("Rejects backticks")
    func rejectsBackticks() throws {
        #expect(throws: PackFetchError.self) {
            try makeFetcher().validateRef("`whoami`")
        }
    }

    @Test("Rejects dollar sign")
    func rejectsDollarSign() throws {
        #expect(throws: PackFetchError.self) {
            try makeFetcher().validateRef("$HOME")
        }
    }

    @Test("Rejects empty string")
    func rejectsEmpty() throws {
        #expect(throws: PackFetchError.self) {
            try makeFetcher().validateRef("")
        }
    }
}

@Suite("PackFetcher identifier validation")
struct PackFetcherIdentifierValidationTests {

    private func makeFetcher() -> PackFetcher {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mcs-fetcher-test-\(UUID().uuidString)")
        let env = Environment(home: tmpDir)
        return PackFetcher(
            shell: ShellRunner(environment: env),
            output: CLIOutput(colorsEnabled: false),
            packsDirectory: tmpDir
        )
    }

    // MARK: - Valid identifiers

    @Test("Accepts simple hyphenated name")
    func acceptsHyphenatedName() throws {
        try makeFetcher().validateIdentifier("my-pack")
    }

    @Test("Accepts dotted name")
    func acceptsDottedName() throws {
        try makeFetcher().validateIdentifier("my.pack")
    }

    @Test("Accepts alphanumeric name")
    func acceptsAlphanumericName() throws {
        try makeFetcher().validateIdentifier("pack123")
    }

    // MARK: - Rejected identifiers

    @Test("Rejects empty string")
    func rejectsEmpty() throws {
        #expect(throws: PackFetchError.self) {
            try makeFetcher().validateIdentifier("")
        }
    }

    @Test("Rejects path traversal")
    func rejectsPathTraversal() throws {
        #expect(throws: PackFetchError.self) {
            try makeFetcher().validateIdentifier("../../etc")
        }
    }

    @Test("Rejects slash")
    func rejectsSlash() throws {
        #expect(throws: PackFetchError.self) {
            try makeFetcher().validateIdentifier("foo/bar")
        }
    }

    @Test("Rejects leading dash")
    func rejectsLeadingDash() throws {
        #expect(throws: PackFetchError.self) {
            try makeFetcher().validateIdentifier("-pack")
        }
    }
}
