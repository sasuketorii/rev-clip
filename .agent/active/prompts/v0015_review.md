# Reviewer Task: Revert Revpy → Revclip

## Purpose
ALL "Revpy" references are being reverted back to "Revclip". No one downloaded "Revpy", so this is a clean revert of the rename only.

## Verify
1. **No "Revpy" remains** in any source, config, CI, or localization file
2. **Feature changes preserved**: Template editor rename, icon-only toggle, folder spacing, hotkey change, title padding, clipboard number-first format, menu text length 40, snippet tooltips — all must still be present
3. **PRODUCT_NAME line removed** from project.yml (defaults to target name "Revclip")
4. **TEST_HOST** reverted to Revclip.app/Contents/MacOS/Revclip
5. **CI workflow** references Revclip.app and Revclip-*.dmg
6. **Build succeeds**

Run: `cd src/Revclip && xcodegen generate && xcodebuild -scheme Revclip -configuration Debug build CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5`

Also run: `grep -r "Revpy" src/Revclip/ .github/ --include="*.m" --include="*.h" --include="*.strings" --include="*.xib" --include="*.plist" --include="*.yml"` — must return ZERO results.

## Output
`LGTM` or `FINDING: [severity] description`

## Diff

