# Releasing Lines

Lines ships as a Homebrew cask: a zipped, signed and notarized `Lines.app`
attached to a GitHub release, and a cask in the `zmscode/homebrew-lines` tap
that points at it. Homebrew disables casks whose apps fail Gatekeeper (since
1 September 2026), so every release must be signed with a Developer ID and
notarized.

## One-time setup

1. **Developer ID.** Join the Apple Developer Program, then create a
   *Developer ID Application* certificate (Xcode › Settings › Accounts ›
   Manage Certificates). Check it's in the keychain:

   ```sh
   security find-identity -v -p codesigning
   ```

2. **Notary credentials.** Store an app-specific password (from
   appleid.apple.com) in the keychain under a profile name:

   ```sh
   xcrun notarytool store-credentials lines-notary --apple-id YOU@example.com --team-id TEAMID
   ```

3. **Environment.** Add to your shell profile (fish shown):

   ```fish
   set -gx LINES_SIGN_IDENTITY "Developer ID Application: Your Name (TEAMID)"
   set -gx LINES_NOTARY_PROFILE lines-notary
   ```

4. **Repositories.** The app's repository is `zmscode/Lines` and the tap is
   `zmscode/homebrew-lines` (change `github` and `tap` at the top of the
   justfile to use others). Create both on GitHub; the tap needs only a
   `Casks/` folder.

## Each release

1. Set the version in `VERSION` (for example `1.1.0`) and commit.
2. `just release` — rebuilds in release mode, signs with the hardened
   runtime, notarizes and staples, zips to `build/Lines-<version>.zip`, and
   writes the version and SHA-256 into `Casks/lines.rb`. Commit the cask.
3. `just publish` — creates the `v<version>` GitHub release with the zip and
   pushes the cask to the tap.

Users then install and update with:

```sh
brew install --cask zmscode/lines/lines
brew upgrade --cask lines
```

`just cask-check` runs Homebrew's style rules over the cask.

## Notes

- **Build number.** `CFBundleVersion` is the number of commits, so it always
  rises.
- **Apple silicon only.** macOS 27 runs only on Apple silicon, and the cask
  requires it (`depends_on macos: :golden_gate`).
- **Until notarized.** 1.0.0 shipped ad hoc–signed, with a caveat in the cask
  and the README about approving it once. Remove both with the first notarized
  release.
- **Testing the pipeline.** `LINES_ALLOW_UNSIGNED=1 just release` builds an
  ad hoc–signed zip. Gatekeeper rejects it on other Macs, so don't publish it.
- **The official homebrew/cask repository.** Once Lines is notable enough, the
  same cask can be submitted there (it then installs as
  `brew install --cask lines`); it must pass `brew audit --cask --new lines`.
