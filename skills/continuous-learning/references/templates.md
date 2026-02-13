# Memory Templates & Examples

Reference file for the continuous-learning skill. Load this when creating or updating memories
to use the appropriate template structure.

---

## Learning Memory Template

```markdown
## Problem
[Clear description of the problem]

## Trigger Conditions
[When does this occur? Include exact error messages, symptoms, scenarios]

## Solution
[Step-by-step solution]

## Verification
[How to verify the solution worked]

## Example
[Concrete code example]

## Notes
[Caveats, edge cases, related considerations]

## References
[Links to documentation, articles, resources]
```

---

## Decision Memory Template (ADR-Inspired)

Use for architectural decisions, tool choices, or patterns with meaningful trade-offs.

```markdown
## Decision
[One-sentence summary of what was decided]

## Context
[Why this decision was needed. What problem or question prompted it?]

## Options Considered
- **Option A**: [Brief description] - [Pros/Cons]
- **Option B**: [Brief description] - [Pros/Cons]

## Choice
[Which option was selected and why]

## Consequences
[What are the implications? What does this enable or prevent?]

## Scope
[Where does this apply? Whole project? Specific modules? Specific scenarios?]

## Examples
[Code examples showing the decision in practice]

## References
[Related documentation, discussions, or resources]
```

---

## Simplified Decision Template

Use for straightforward preferences without complex trade-offs.

```markdown
## Decision
[What was decided]

## Rationale
[Why this choice]

## Examples
[How to apply it]
```

---

## Example 1: Learning — Auto Layout Constraint Accumulation

```
mcp__serena__write_memory(
  name: "learning_autolayout_constraint_accumulation",
  content: "## Problem
Auto Layout constraints accumulating on each view update, causing memory growth and eventual crash.

## Trigger Conditions
- Memory usage grows continuously during scroll or repeated updates
- Xcode Memory Graph shows thousands of NSLayoutConstraint objects
- Using `translatesAutoresizingMaskIntoConstraints = false` with manual constraint setup

## Solution
1. Store constraint references and deactivate before creating new ones
2. Use `NSLayoutConstraint.deactivate(existingConstraints)` before `activate(newConstraints)`
3. Consider using constraint arrays: `var heightConstraints: [NSLayoutConstraint] = []`
4. For reusable views, implement `prepareForReuse()` to clear constraints

## Verification
Monitor memory in Instruments; constraint count should stay stable during updates.

## Example
```swift
private var dynamicConstraints: [NSLayoutConstraint] = []

func updateLayout() {
    NSLayoutConstraint.deactivate(dynamicConstraints)
    dynamicConstraints = [
        view.heightAnchor.constraint(equalToConstant: newHeight)
    ]
    NSLayoutConstraint.activate(dynamicConstraints)
}
```

## Notes
- Common in collection view cells with dynamic content
- Also check for retain cycles in closure-based constraint setup

## References
- https://developer.apple.com/documentation/uikit/nslayoutconstraint"
)
```

---

## Example 2: Decision — PDF Over SVG for Assets

```
mcp__serena__write_memory(
  name: "decision_assets_pdf_over_svg",
  content: "## Decision
Use PDF format for vector assets instead of SVG in this iOS project.

## Context
Needed to decide on vector asset format for icons and illustrations that need to scale across device sizes.

## Options Considered
- **PDF**: Native Xcode support, single file, automatic @1x/@2x/@3x generation
- **SVG**: Web standard, smaller files, but requires iOS 13+ or third-party library

## Choice
PDF chosen because:
1. Native Asset Catalog support without additional dependencies
2. Automatic scale generation by Xcode
3. Works on all iOS versions we support
4. Simpler build pipeline

## Consequences
- Designers export as PDF from Figma/Sketch
- Larger file sizes than SVG (acceptable trade-off)
- No runtime SVG rendering flexibility

## Scope
All vector assets in the project (icons, illustrations, logos).

## References
- https://developer.apple.com/documentation/xcode/asset-management"
)
```

---

## Example 3: Simple Preference Decision

```
mcp__serena__write_memory(
  name: "decision_codestyle_explicit_self",
  content: "## Decision
Always use explicit `self` when capturing in closures, even when not required by the compiler.

## Rationale
- Makes capture semantics immediately visible
- Prevents accidental strong reference cycles
- Consistent with SwiftLint's `explicit_self` rule

## Examples
```swift
// ✅ Preferred
fetchData { [weak self] result in
    self?.handleResult(result)
    self?.isLoading = false
}

// ❌ Avoid (even if compiler allows)
fetchData { [weak self] result in
    guard let self else { return }
    handleResult(result)  // implicit self
    isLoading = false     // implicit self
}
```"
)
```
