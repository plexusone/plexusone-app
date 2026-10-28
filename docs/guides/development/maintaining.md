# Maintaining

How to keep the repository healthy and ship PlexusOne Desktop releases. For
setting up a development environment and making changes, see
[Contributing](contributing.md).

## Documentation layout

The MkDocs site is built from `docs/`, with the navigation in `mkdocs.yml`.

| Directory | Contents |
|-----------|----------|
| `docs/guides/` | User guides (getting started, desktop, mobile, reference) and developer guides (`development/`) |
| `docs/design/architecture/` | How the system is built |
| `docs/design/adrs/` | Architecture decision records, one decision per numbered file |
| `docs/specs/` | PRD, TRD, feature specs (`features/`), and initiative roadmaps (`initiatives/`) |
| `docs/releases/` | Release notes per version and the generated changelog |
| `docs/images/` | Screenshots and images |

Check the site before committing documentation changes. `--strict` fails on
broken links:

```bash
mkdocs build --strict
```

## Everyday checks

Run the checks for each component you changed:

```bash
# Desktop (Swift)
cd apps/desktop && swift build && swift test

# Native iOS
cd apps/ios && xcodebuild -project PlexusOneiOS.xcodeproj -scheme PlexusOneiOS \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build

# Flutter
cd apps/flutter && flutter analyze && flutter test

# TUI Parser (Go)
cd services/tuiparser && go build ./... && go test ./... && golangci-lint run
```

## Continuous integration

| Workflow | Runs on | Builds with | Does |
|----------|---------|-------------|------|
| Desktop CI (`desktop.yaml`) | Pushes and pull requests to `main` that touch `apps/desktop/` | The shared org Swift workflow (Xcode 16.2 today) | Builds and tests the desktop app |
| Desktop Release (`desktop-release.yaml`) | `v*` tags, or a manual run | `macos-26` runners (Xcode 26) | Builds, signs, and packages the DMGs; on a tag, publishes the GitHub release |

The two workflows use different Xcode versions. Desktop CI is the stricter
check for Swift language and dependency support; the release workflow is the
one that produces what users install.

## Dependencies

Dependabot opens weekly pull requests for the desktop and iOS Swift packages,
the Flutter app, the Go service, and GitHub Actions (`.github/dependabot.yml`).

- **SwiftTerm** is pinned to an exact version in `apps/desktop/Package.swift`.
  SwiftTerm 1.99 and later declare `swift-tools-version: 6.2`, which needs
  Xcode 26, so Dependabot skips them until Desktop CI builds with Xcode 26.
  The desktop app overrides SwiftTerm behavior (input, scrolling, process
  handling), so test a SwiftTerm update by hand as well as with `swift test`.
- **The iOS Xcode project** pins its packages in
  `PlexusOneiOS.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`,
  separately from `apps/ios/Package.resolved`. Update both when changing an
  iOS dependency.
- **Before merging a dependency pull request**, check that Desktop CI passed.
  A failing update left on `main` blocks every later release.

## Releases

Releases are versioned `vX.Y.Z` and follow [Semantic Versioning](https://semver.org/).
Pushing a `vX.Y.Z` tag builds the DMGs and publishes the GitHub release.

### 1. Prepare the release

Bring `main` up to date first. The changelog records commit hashes, so write
it after the last rebase:

```bash
git pull --rebase origin main
schangelog parse-commits --since=<previous tag>
```

Then, in topical commits:

1. **Changelog.** Add the version to `CHANGELOG.json`, then regenerate and copy it:

    ```bash
    schangelog validate CHANGELOG.json
    schangelog generate CHANGELOG.json -o CHANGELOG.md
    cp CHANGELOG.md docs/releases/changelog.md
    ```

2. **Release notes.** Write `docs/releases/vX.Y.Z.md` following the previous
   release. The release workflow uses this file as the GitHub release page,
   followed by GitHub's generated list of changes, so link to docs with full
   GitHub URLs rather than relative paths.
3. **Navigation.** Add the release notes to the Releases section of `mkdocs.yml`.
4. **Version.** Set `CFBundleShortVersionString` and `CFBundleVersion` in
   `apps/desktop/Sources/PlexusOneDesktop/Info.plist`. Edit the two strings
   directly; `PlistBuddy` rewrites the file's formatting.

If `main` moves before you push and you rebase again, the changelog hashes
change. Update them in the changelog commit itself rather than adding a
separate commit.

### 2. Push and wait for CI

```bash
git push origin main
gh run watch "$(gh run list --workflow 'Desktop CI' --branch main --limit 1 --json databaseId --jq '.[0].databaseId')"
```

Do not tag until Desktop CI passes on the commit you intend to release.

### 3. Trial run of the release build

Build the DMGs on the release runners without publishing anything:

```bash
gh workflow run desktop-release.yaml -f version=X.Y.Z
gh run watch "$(gh run list --workflow 'Desktop Release' --limit 1 --json databaseId --jq '.[0].databaseId')"
```

A manual run builds the arm64, Intel, and universal DMGs and uploads them as
workflow artifacts. It does not create a tag or a release. To try a DMG:

```bash
gh run download <run-id> --dir /tmp/plexusone-trial
```

This is the first build with the release runners' Xcode, which can be newer
than Desktop CI's, so it catches compiler and packaging problems before a tag
makes them public.

### 4. Tag and publish

```bash
git tag vX.Y.Z
git push origin vX.Y.Z
```

The Desktop Release workflow then:

1. Builds release binaries for arm64 and x86_64, and a universal binary.
2. Assembles `PlexusOne Desktop.app`, sets the bundle version from the tag,
   and ad-hoc signs and verifies the bundle.
3. Packages each bundle as a DMG with an Applications link:
   `PlexusOneDesktop-X.Y.Z-macos-{arm64,x86_64,universal}.dmg`.
4. Publishes the GitHub release "PlexusOne Desktop vX.Y.Z" with
   `docs/releases/vX.Y.Z.md` as its notes and the three DMGs attached. Tags
   containing `alpha`, `beta`, or `rc` are published as pre-releases.

### 5. Verify the release

1. Download a DMG from the release page with a browser, so it is quarantined
   like a user's download.
2. Drag the app to Applications and open it. Builds are ad-hoc signed and not
   notarized, so macOS asks first: open **System Settings > Privacy & Security**
   and click **Open Anyway**.
3. Check **PlexusOne Desktop > About** shows the new version, and try the
   release's main changes.

### 6. Publish the documentation

The documentation site is not deployed by CI:

```bash
mkdocs gh-deploy
```

### If a release fails

- **The trial run or tag build fails before publishing:** fix the problem on
  `main`, then release the next patch version with a new tag. Do not reuse a
  version that has been pushed as a tag.
- **A published release has a problem:** release a fixed patch version and
  note the problem in its release notes.

## Signing

Release builds are ad-hoc signed so Gatekeeper offers **Open Anyway** instead
of reporting the app as damaged. Developer ID signing and notarization, which
would remove the first-launch prompt, require an Apple Developer Program
membership and are not set up yet.
