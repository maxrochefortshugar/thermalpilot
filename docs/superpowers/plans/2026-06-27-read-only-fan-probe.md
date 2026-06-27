# Read-Only Fan Probe Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a standalone macOS read-only fan and thermal probe under `/Users/maxshugar/Development/coldfront`.

**Architecture:** The command-line app is Swift. A small C target handles the private AppleSMC struct layout and exposes read-only functions only. Swift owns decoding, snapshot assembly, output formatting, and tests.

**Tech Stack:** Swift Package Manager, Swift 6, XCTest, IOKit, CoreFoundation.

---

### Task 1: Package Skeleton And Decoder Tests

**Files:**
- Create: `Package.swift`
- Create: `Tests/FanProbeCoreTests/SMCValueDecoderTests.swift`
- Create: `Sources/FanProbeCore/Empty.swift`

- [ ] **Step 1: Write failing decoder tests**

Cover FourCC conversion, `fpe2`, `sp78`, unsigned integers, and `flt ` values.

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter SMCValueDecoderTests`
Expected: FAIL because `SMCValueDecoder` and related types do not exist yet.

### Task 2: Decoder Implementation

**Files:**
- Create: `Sources/FanProbeCore/SMCValueDecoder.swift`

- [ ] **Step 1: Implement minimal decoder**

Add `SMCDecodedValue`, `SMCValueDecoder`, and `SMCKeyCode`.

- [ ] **Step 2: Run tests**

Run: `swift test --filter SMCValueDecoderTests`
Expected: PASS.

### Task 3: Read-Only SMC Bridge

**Files:**
- Create: `Sources/CSMC/include/CSMC.h`
- Create: `Sources/CSMC/CSMC.c`
- Create: `Sources/FanProbeCore/SMCClient.swift`

- [ ] **Step 1: Add C bridge with read functions only**

Expose `CSMCOpen`, `CSMCClose`, `CSMCReadKey`, and `CSMCReadKeyAtIndex`. Do not expose any write function.

- [ ] **Step 2: Add Swift wrapper**

Wrap the C calls in `SMCClient`, returning Swift values and errors.

### Task 4: Snapshot And CLI

**Files:**
- Create: `Sources/FanProbeCore/FanProbe.swift`
- Create: `Sources/coldfront/main.swift`
- Create: `README.md`

- [ ] **Step 1: Assemble host and SMC snapshot**

Collect model, chip, architecture, thermal state, fan keys, and a bounded set of readable temperature/power keys.

- [ ] **Step 2: Add CLI output**

Print a compact read-only view by default and support explicit key reads through positional key arguments.

### Task 5: Verification

- [ ] **Step 1: Run tests**

Run: `swift test`
Expected: PASS.

- [ ] **Step 2: Build release binary**

Run: `swift build -c release`
Expected: PASS.

- [ ] **Step 3: Run local read-only probe**

Run: `.build/release/coldfront`
Expected: Prints host data and either SMC values or unavailable messages without requesting sudo.
