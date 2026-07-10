# SQLite Permanent History Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Preserve every clipboard and favorite entry until the user explicitly deletes or clears it, without making normal app use slower as history grows.

**Architecture:** Replace the full-history JSON snapshot with a local SQLite database in Application Support. The manager keeps only a small query page in memory; inserting, updating, deleting, searching, and filtering operate directly on indexed rows. On first launch after upgrade, legacy `history.json` is imported transactionally and renamed only after a successful import.

**Tech Stack:** Swift 5.9, SQLite3 system library, SwiftUI, AppKit.

---

### Task 1: Add persistent SQLite repository

**Files:**
- Create: `Sources/Core/ClipboardStore.swift`
- Modify: `Sources/Core/ClipboardManager.swift`
- Modify: `Scripts/build.sh`

**Step 1:** Create the schema with `clipboard_items`, indexes for newest-first history, favorites, and duplicate lookup.

**Step 2:** Implement parameter-bound CRUD, page queries, count queries, and a transactional import for legacy decoded items.

**Step 3:** Replace JSON snapshot writes and the fixed-length trim with repository operations; retain only the active page in `ClipboardManager.items`.

**Step 4:** Compile with `-lsqlite3`.

### Task 2: Make view queries page-backed

**Files:**
- Modify: `Sources/Views/PopoverView.swift`
- Modify: `Sources/Views/SettingsView.swift`

**Step 1:** Keep query state in the manager and refresh its page when the favorites/tag/search controls change.

**Step 2:** Request the next page when the final displayed row appears.

**Step 3:** Replace the destructive history limit selector with permanent-storage information and database-backed counts.

### Task 3: Preserve cleanup and verify

**Files:**
- Modify: `Sources/Core/ClipboardManager.swift`
- Modify: `README.md`

**Step 1:** Delete image and thumbnail assets only after their database row is removed.

**Step 2:** Verify a legacy JSON history migrates once, multiple pages append without duplicates, and clear/delete affect only explicitly selected records.

**Step 3:** Compile the complete macOS application with the project build command (without install/package side effects).
