@testable import mcs
import Testing

struct GlobMatcherTests {
    @Test("Exact path matches itself")
    func exactPath() {
        #expect(GlobMatcher.matches("README.md", path: "README.md"))
        #expect(!GlobMatcher.matches("README.md", path: "readme.md"))
        #expect(!GlobMatcher.matches("README.md", path: "docs/README.md"))
    }

    @Test("FNM_PATHNAME — * does not cross /")
    func starDoesNotCrossSlash() {
        #expect(GlobMatcher.matches("*.md", path: "README.md"))
        #expect(!GlobMatcher.matches("*.md", path: "docs/README.md"))
        #expect(GlobMatcher.matches("docs/*", path: "docs/guide.md"))
        #expect(!GlobMatcher.matches("docs/*", path: "docs/sub/guide.md"))
    }

    @Test("Question mark matches a single non-/ character")
    func questionMark() {
        #expect(GlobMatcher.matches("file?.txt", path: "file1.txt"))
        #expect(!GlobMatcher.matches("file?.txt", path: "file12.txt"))
        #expect(!GlobMatcher.matches("file?.txt", path: "file/.txt"))
    }

    @Test("Character class matches any single char in set")
    func characterClass() {
        #expect(GlobMatcher.matches("file[12].txt", path: "file1.txt"))
        #expect(GlobMatcher.matches("file[12].txt", path: "file2.txt"))
        #expect(!GlobMatcher.matches("file[12].txt", path: "file3.txt"))
    }

    @Test("Trailing slash silences entire directory tree")
    func directorySuffix() {
        #expect(GlobMatcher.matches("docs/", path: "docs"))
        #expect(GlobMatcher.matches("docs/", path: "docs/guide.md"))
        #expect(GlobMatcher.matches("docs/", path: "docs/sub/guide.md"))
        #expect(GlobMatcher.matches("docs/", path: "docs/sub/deep/file.md"))
        #expect(!GlobMatcher.matches("docs/", path: "documentation.md"))
        #expect(!GlobMatcher.matches("docs/", path: "other/docs.md"))
    }

    @Test("Empty/whitespace patterns never match")
    func emptyPattern() {
        #expect(!GlobMatcher.matches("", path: "anything"))
        #expect(!GlobMatcher.matches("   ", path: "anything"))
        #expect(!GlobMatcher.matches("/", path: "anything"))
    }

    @Test("Glob with extension matches all files of that type at one level")
    func extensionGlob() {
        #expect(GlobMatcher.matches("diagrams/*.png", path: "diagrams/architecture.png"))
        #expect(!GlobMatcher.matches("diagrams/*.png", path: "diagrams/architecture.jpg"))
        #expect(!GlobMatcher.matches("diagrams/*.png", path: "diagrams/sub/architecture.png"))
    }

    @Test("Whitespace around the pattern is trimmed before matching")
    func patternWhitespaceTrimmed() {
        // Without trim, ` README.md ` would never match anything via fnmatch.
        #expect(GlobMatcher.matches(" README.md ", path: "README.md"))
        #expect(GlobMatcher.matches("\tdocs/*\n", path: "docs/guide.md"))
    }
}
