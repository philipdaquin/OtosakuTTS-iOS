---
name: release-otosaku
description: "OtosakuTTS Mac release: signing, notarization, Sparkle appcast, and GitHub Release publishing."
---

# OtosakuTTS Mac Release

Use when shipping the macOS Example app. The pipeline is the StorageScanner adaptation of the CodexBar release flow.

## Start

1. Work from this repo.
2. Check `version.env`, `CHANGELOG.md`, the latest tag, and `scripts/release.sh`.
3. Keep `CHANGELOG.md` user-facing. The top released section must match `MARKETING_VERSION`.
4. Use `scripts/release.sh`. Do not bypass it with a one-off `xcodebuild`.
5. Never print signing keys, notarization keys, or `.p8` contents. `release.env` is local only.

## Inputs

Copy `release.env.example` to `release.env` and fill in:

- `DEVELOPER_ID_IDENTITY`
- `NOTARYTOOL_PROFILE` or `NOTARYTOOL_API_KEY_FILE`, `NOTARYTOOL_API_KEY_ID`, `NOTARYTOOL_API_ISSUER_ID`
- `SPARKLE_PRIVATE_KEY_FILE` or `SPARKLE_PRIVATE_KEY`
- `SPARKLE_PUBLIC_ED_KEY`
- `APPCAST_URL`

GitHub Actions reads the same names from repository secrets. See the Mac Release section of `README.md`.

## Ship

```bash
scripts/release-doctor.sh --github
scripts/release.sh local
scripts/release.sh publish
```

`local` stops after the signed app, DMG, Sparkle ZIP, and appcast in `.release/`.
`publish` notarizes the DMG, creates the GitHub Release, uploads the assets, and writes `appcast.xml`.
`upload` attaches those assets to an existing release for `v$MARKETING_VERSION`.

Automatic publishing is `.github/workflows/release.yml`.

## Verify

A release is not done until the published chain checks out:

```bash
gh release view v<VERSION> --repo philipdaquin/OtosakuTTS-iOS --json tagName,name,isDraft,isPrerelease,url,assets,body
```

Confirm `appcast.xml` points at the new GitHub ZIP and includes a Sparkle `edSignature` and length.

## Closeout

1. Let `scripts/release.sh publish` create the tag and GitHub Release.
2. Confirm the workflow committed `appcast.xml`, or commit it if you published locally.
3. Bump `version.env` to the next build and add a fresh `## Unreleased` section only after the released section stays on top.
4. Do not leave `release.env`, `.p8` files, or `.release/` in git.
