# History Tagging Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Allow every history item to receive tags and make tag saving deterministic with clear feedback.

**Architecture:** Keep tags in the existing SQLite `tags_json` field. Make the row context menu available for all records, route saves through a result-returning manager method, and remove duplicate SwiftUI tap handlers that currently invoke actions twice.

**Tech Stack:** SwiftUI, Swift 5.9, SQLite3.

---

### Task 1: Validate tag persistence

**Files:**
- Modify: `Sources/Core/ClipboardManager.swift`

**Step 1:** Normalize empty whitespace and identify duplicate tags before persistence.

**Step 2:** Return a user-facing save result for saved, duplicate, empty, and failed cases.

### Task 2: Expose reliable tag actions

**Files:**
- Modify: `Sources/Views/PopoverView.swift`

**Step 1:** Display add/remove tag actions for all history rows.

**Step 2:** Keep the tag sheet open on a failed save and render an inline message.

**Step 3:** Remove duplicate `onTapGesture` handlers from buttons.

### Task 3: Verify

**Files:**
- Modify: `Sources/Views/PopoverView.swift`

**Step 1:** Compile the complete app and confirm no warning/error is introduced.
