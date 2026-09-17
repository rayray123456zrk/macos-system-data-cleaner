---
name: macos-system-data-cleaner
description: Diagnose unexpectedly large macOS System Data, identify caches and application data consuming disk space, and perform user-authorized cleanup with recoverable safeguards. Use for Mac storage audits, oversized System Data, cache cleanup, APFS snapshot checks, or finding large files hidden under Library and private/var. Do not use for ordinary document organization or non-macOS systems.
---

# macOS System Data Cleaner

Audit first, classify findings, and clean only the targets the user authorizes. Treat macOS Storage's “System Data” as an opaque category that may include application support files, containers, caches, models, temporary files, local snapshots, logs, and update remnants—not merely operating-system files.

When this repository's **MacSpace Guard** app is installed, prefer it for continuous monitoring, history, interactive selection, and recoverable cleanup. Use the bundled shell audit for a one-time read-only diagnosis or when the app is unavailable.

## Operating invariants

- Start with read-only inspection. Never infer permission to delete from a request to diagnose, inspect, or explain.
- Preserve unrelated files and existing user data. Resolve every cleanup target to an explicit absolute path before mutation.
- Distinguish reproducible cache from user content. Do not label chat attachments, databases, game installs, documents, or project files as safe cache merely because they live under `Library`.
- Prefer an application’s built-in storage manager for chat media, cloud-sync data, browser profiles, games, and databases.
- For authorized cleanup, close the affected application when practical and move items to a dated folder in `~/.Trash` by default. Permanently delete only when explicitly requested.
- Explain that moving files to Trash does not free disk space until Trash is emptied.
- Require separate, explicit authorization immediately before administrator-level or permanent deletion. Never broaden a target such as `/Library/Updates` to `/Library`.
- Do not delete the active agent runtime, current terminal resources, or cache files actively used by the current session.

## Workflow

### 1. Establish actual disk pressure

Run the bundled read-only audit when available:

```bash
zsh scripts/audit_macos_storage.sh
```

Otherwise inspect the writable Data volume rather than relying only on the sealed root volume:

```bash
df -h /System/Volumes/Data
tmutil listlocalsnapshots /
```

Use bounded `du` queries against likely locations. Avoid an unbounded scan of `/` when targeted directories can explain the usage.

### 2. Identify large categories

Inspect these locations, suppressing expected permission errors:

- `~/Library/Caches`, `~/Library/Logs`
- `~/Library/Application Support`
- `~/Library/Containers`, `~/Library/Group Containers`
- `~/Library/Developer`, `~/Library/Mobile Documents`
- `~/.cache`, `~/.npm`, and other tool-specific cache directories
- `/private/var/folders`, `/private/var/vm`, `/private/var/db`
- `/Library/Updates`, `/Library/Developer`, `/Library/Caches`
- `/Applications` and ordinary user folders for comparison

Drill down only into the largest entries. Check unusually large individual files when directory totals do not explain the result.

### 3. Classify before recommending

Use three buckets:

1. **Low-risk and reproducible:** download caches, package-manager caches, logs, abandoned temporary directories, updater staging files, and code-signing clones.
2. **Reproducible but costly:** local AI models, speech models, browser components, SDKs, simulator data, and development runtimes. State that removal may cause a large re-download or break offline use.
3. **User or application data:** chat attachments, mail stores, browser profiles, databases, games, cloud-sync content, documents, and media. Recommend application-managed cleanup or explicit item selection.

Report absolute path, measured size, classification, expected consequence, and estimated recoverable space. Keep estimates separate from confirmed measurements and avoid double-counting nested directories.

### 4. Clean in increasing-risk order

After the user chooses targets:

1. Re-measure and confirm each exact path still exists.
2. Create a unique dated folder under `~/.Trash`.
3. Move low-risk targets individually, using distinct destination names to prevent collisions.
4. Verify that each source disappeared and measure the Trash archive.
5. Leave failed or protected targets untouched and report them.
6. Handle system-owned targets separately; if authorization or authentication fails, stop rather than substituting a broader or permanent command.

If an interactive `sudo` command is waiting and the user cancels, immediately send an interrupt and verify the target remains intact.

### 5. Verify and hand off

Recheck the Data volume, source paths, and Trash archive. State:

- what moved or was deleted;
- what was skipped and why;
- how much is currently in Trash;
- that free space changes only after emptying Trash;
- whether an application may recreate or redownload the files.

Recommend rebooting or reopening affected applications only when it is useful for verification.
