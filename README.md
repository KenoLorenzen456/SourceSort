# SourceSort

A menu-bar utility for macOS that files your downloads by **the website they came from**. It can also sort by filename, extension, file type and size.

> SourceSort processes file metadata locally on your Mac. Nothing is uploaded.

It has no accounts, no telemetry, no network access and no AI.

## What it does

- Watches one or more folders (by default `~/Downloads`) and looks at each new file that lands directly inside them.
- Reads where the file came from and runs your rules from top to bottom. **The first matching rule wins.**
- A rule can:
  - move the file to a folder
  - add a Finder tag
  - leave the file in place

  It can also rename the file with a template.
- Every action appears in the menu bar and in the Activity list, and every move can be undone.

## Requirements

- macOS 15 or later.
- To build: Xcode **or** just the Command Line Tools (`xcode-select --install`). Swift 6 toolchain. No other dependencies.

## Rules

| Condition | Operators |
|---|---|
| Source domain | is · contains |
| Source URL | contains |
| Originating app | is |
| Filename | is · contains · starts with · ends with |
| Extension | is (one of) |
| File type | is (image, video, audio, document, archive, disk image, installer…) |
| Size | greater than · less than |

- **Values:** comma-separated values mean "any of these".
- **Domain matching:** `Source domain is github.com` also matches subdomains such as `objects.githubusercontent.com`. Matching ignores case.
- **Combining conditions:** a rule matches when **All** of its conditions are true (the default), or when **Any** of them is.
- **Priority:** drag rules in the list to change their order.
- **Testing:** *Test Rule* in the rule editor runs a rule against any file you pick. It shows each condition as a pass or fail.

### Safety

- **Never overwrites.** If the name is taken, the file becomes `invoice 2.pdf`, `invoice 3.pdf` and so on.
- **Atomic moves.** Moves within a volume use `renamex_np(RENAME_EXCL)`. Moves across volumes copy the file, verify the copy, and only then remove the original.
- **No loops.** Files SourceSort has handled get an extended attribute (`com.sourcesort.handled`), so they are never sorted twice, even after an Undo.
- **Robust Undo.** Undo finds the file even if it was moved again (it tracks the inode and a bookmark). It recreates a missing original folder, and it uses a new name if the original name is taken. If the file no longer exists, Undo says so.
- **Partial downloads are ignored.** `.download`, `.crdownload`, `.part` and similar files are skipped. A file is only processed once its size has stopped changing for the configured wait time (2 s by default).

### Pause

**Pause Sorting** stops SourceSort from touching anything. Files that arrive while it is paused are **ignored, not queued**: resuming does not go back and sort them. This is deliberate. Resuming should never surprise you by moving a batch of files you may already have opened.

## How source detection works (and its limits)

SourceSort reads two pieces of metadata that macOS and browsers attach to downloads:

1. **`kMDItemWhereFroms`** holds the download URL and usually the page it was downloaded from (the referrer).
   - The "source domain" is the **referrer's** host when there is one. That way `github.com` wins over a CDN such as `objects.githubusercontent.com`.
   - Otherwise it is the download URL's host.
2. **`com.apple.quarantine`** records which app downloaded the file (for example Safari or Google Chrome). This is the "originating app".

Limitations:

- **Files without metadata can only match non-source conditions.** This includes files copied from another disk, created by an app, or unpacked from an archive. By default, **Only sort downloaded files** skips files that have neither piece of metadata.
- **Safari's "Open safe files after downloading"** unpacks zip archives. The unpacked folder does not carry the source website. Turn the option off (Safari ▸ Settings ▸ General) if you want archives sorted by website.
- **Browsers differ:**
  - Safari, Chrome, Edge, Brave, Arc and Firefox write `kMDItemWhereFroms` in normal windows.
  - Private or incognito windows may leave out the referrer or the whole attribute.
  - Some sites deliver files through a redirect or a blob URL. In that case the only host recorded may be a CDN, or nothing useful at all.
- **Command-line downloads** (`curl`, `wget`) and most sync tools write neither attribute.
- **Only files directly inside a watched folder** are considered. Subfolders are ignored, so your sorted folders are never re-sorted.

## Build

```bash
Scripts/build-app.sh
```

This builds a release binary with SwiftPM and assembles `dist/SourceSort.app`: Info.plist, generated app icon and an ad-hoc code signature. Version 1.0, bundle ID `com.sourcesort.app`.

## Tests

```bash
Scripts/test.sh
```

The tests cover the rule engine, URL→domain parsing, collision naming, moving, Undo (renamed, re-moved and deleted files) and persistence. They use Swift Testing, and the script adds the flags needed to run them with only the Command Line Tools installed.

## DMG

```bash
Scripts/make-dmg.sh
```

This creates `dist/SourceSort.dmg`: a compressed disk image named "SourceSort" containing the app and a shortcut to Applications. To install, drag SourceSort onto Applications.

### Gatekeeper

The app is signed **ad hoc**, not with a Developer ID, and is not notarized. When you download the DMG from the internet, macOS will refuse to open it the first time. To allow this one app:

1. Try to open SourceSort. Dismiss the warning.
2. Open **System Settings ▸ Privacy & Security** and click **Open Anyway** next to SourceSort.

A copy you built yourself isn't quarantined, so it opens without this step. Never turn Gatekeeper off globally.

### Later: Developer ID, notarization, updates

The build is set up so these can be added without restructuring:

- **Developer ID:** `SIGN_IDENTITY="Developer ID Application: …" Scripts/build-app.sh` signs with the hardened runtime (already on); change `--timestamp=none` to `--timestamp` for notarization.
- **Notarization:** the comments in `Scripts/build-app.sh` list the `notarytool submit` and `stapler staple` steps.
- **Updates:** Sparkle would be the only added dependency, and only when auto-update is wanted.

## Permissions

- **Folder access:** the first time SourceSort reads Downloads, Desktop or Documents, macOS asks whether to allow it. Choose **Allow**. Folders added through the Open panel are remembered with security-scoped bookmarks.
- **Launch at login:** uses `SMAppService`. If macOS asks for approval, SourceSort links to System Settings ▸ General ▸ Login Items.
- **Notifications:** optional, and grouped so a burst of downloads produces one summary.

## Data

- **Rules and activity:** JSON files in `~/Library/Application Support/SourceSort/`.
- **Settings:** stored in `UserDefaults`.
- **Unreadable data files:** set aside as `*.corrupt-<timestamp>` rather than overwritten.
