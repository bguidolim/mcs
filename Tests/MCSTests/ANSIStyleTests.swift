import Foundation
@testable import mcs
import Testing

struct ANSIStyleTests {
    @Test("Enabled style emits SGR sequences")
    func enabled() {
        let style = ANSIStyle(enabled: true)
        #expect(style.reset == "\u{1B}[0m")
        #expect(style.dim == "\u{1B}[2m")
        #expect(style.red == "\u{1B}[0;31m")
        #expect(style.green == "\u{1B}[0;32m")
        #expect(style.yellow == "\u{1B}[1;33m")
    }

    @Test("Disabled style returns empty strings so tests can assert plain text")
    func disabled() {
        let style = ANSIStyle(enabled: false)
        #expect(style.reset.isEmpty)
        #expect(style.dim.isEmpty)
        #expect(style.red.isEmpty)
        #expect(style.green.isEmpty)
        #expect(style.yellow.isEmpty)
        #expect(style.dimRed.isEmpty)
        #expect(style.dimYellow.isEmpty)
    }

    @Test("Combined forms use single SGR sequences (stacking two SGRs would cancel dim)")
    func combinedForms() {
        let style = ANSIStyle(enabled: true)
        #expect(style.dimRed == "\u{1B}[2;31m")
        #expect(style.dimYellow == "\u{1B}[2;33m")
    }
}
