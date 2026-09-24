# Cross-Platform Interactive Messages Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the Marmot v1 interactive-message protocol, a shared MDK implementation and bindings, and a native Level 1 macOS renderer while preserving readable fallback behavior for existing clients.

**Architecture:** A kind-`9` event remains readable Markdown and carries one canonical structured envelope in an `interactive` tag. MDK owns validation, hidden response modifiers, projection, persistence, and FFI records; macOS consumes validated projections and renders native SwiftUI. This delivery validates `interactive_app` as unsupported-with-fallback but does not add a browser runtime.

**Tech Stack:** Marmot Markdown specification, Rust, Serde, Rusqlite, UniFFI, C ABI/cbindgen, Swift 6, SwiftUI, Swift Testing, Xcode 26.

**Spec:** `docs/superpowers/specs/2026-09-23-cross-platform-interactive-messages-design.md`

## Global Constraints

- Work in `liamhelmer/marmot`, `liamhelmer/mdk`, and `liamhelmer/whitenoise-mac`; open separate PRs against each upstream and never merge automatically.
- Start `feature/interactive-messages-v1` from each upstream's current default branch, currently `master`.
- Sign every commit with the configured Radicle SSH key and verify it before pushing.
- Kind `9` content is the complete fallback; kind `1203` is the hidden response modifier; kind `1204` is reserved for app state.
- Feature JSON is canonical RFC 8785 UTF-8. Protocol numbers are nonnegative safe integers. Duplicate keys, floats, and noncanonical bytes are rejected.
- Prompt/response JSON is at most 65,536 bytes; state-update JSON is at most 131,072 bytes.
- A prompt has at most 64 blocks, 32 actions, 32,768 Markdown bytes, and 100 choice options. Labels are at most 256 bytes and each text response at most 16,384 bytes.
- Malformed structured content never hides or invalidates the kind-`9` fallback.
- Baseline blocks are `markdown`, `text_input`, `choice`, `confirmation`, `field_group`, `divider`, `status`, `artifact`, `image`, and `diagram`.
- Baseline actions are `submit`, `approve`, `reject`, `cancel`, and `open`.
- The first macOS delivery renders `interactive_app` through its fallback and does not add `WKWebView`.
- Do not add stored properties or feature methods to `WorkspaceState`, add a `WorkspaceState+*.swift` file, or add computed `var …: some View`. Every new view gets a `#Preview`.
- Do not bump the MDK workspace version. A matching MarmotKit release is a separate user-authorized operation after MDK merges.

## Review Focus

- Malformed base64, duplicate JSON keys, floats, and noncanonical JSON must preserve fallback and disable actions (Tasks 2, 4, 8).
- Unknown actions/inputs, stale revisions, expiry, and oversize values remain ineffective (Tasks 2 and 4).
- Same-time competing responses converge by canonical event ID under every policy (Task 4).
- Group cycles, duplicate IDs, and absent input references fail without unbounded recursion (Task 2).
- Missing graphics/app attachments preserve alt text and never enable execution or privileged actions (Tasks 7 and 9).

---

## Execution Gates

1. Finish Task 1 and open the Marmot protocol PR. Resolve protocol review before freezing MDK fixtures.
2. Finish Tasks 2–6 and open the MDK PR. macOS may be developed with local generated bindings, but its PR must use a published remote binary.
3. After MDK merges and the user authorizes a MarmotKit release, finish Tasks 7–10 and open the macOS PR.

If review changes event kinds or schemas, update Marmot and fixtures first, then downstream expectations. Never preserve compatibility with an unmerged draft.

Before the first task in each repository, use the worktree setup skill to create an isolated worktree, name the upstream remote `origin`, name Liam's fork remote `fork`, fetch `origin/master`, and create `feature/interactive-messages-v1` at `origin/master`. Verify signing configuration with:

```bash
git config gpg.format
git config user.signingkey
git config commit.gpgsign
```

Expected values are `ssh`, `/Users/newuser/.radicle/keys/radicle.pub`, and `true`. Stop rather than creating an unsigned commit if any value differs.

### Task 1: Publish the normative Marmot feature

**Repository:** `liamhelmer/marmot`

**Files:**
- Create: `features/interactive-messages-v1.md`
- Create: `foundation/fixtures/interactive-messages-v1.json`
- Modify: `foundation/application-messages.md`
- Modify: `foundation/registries.md`
- Modify: `foundation/canonical-encoding.md`
- Modify: `features/README.md`
- Modify: `foundation/README.md`
- Modify: `layout.md`

**Interfaces:**
- Consumes: unsigned Nostr-shaped Marmot app events and kind-`9` semantics.
- Produces: exact event/tag schemas, kinds `1203`/`1204`, JSON rules, limits, selection rules, and fixtures.

- [ ] **Step 1: Create the feature skeleton and observe the missing registry**

Add the titled feature document and index links, then run:

```bash
rg -n 'interactive-messages-v1|1203|1204' features foundation layout.md
```

Expected: feature links exist but the kind registry is incomplete.

- [ ] **Step 2: Specify exact wire surfaces**

Define prompt, response, revision, and app-state events. Add these registry rows:

```markdown
| `1203` | Interactive response v1        | Marmot app payload | [interactive-messages-v1.md](../features/interactive-messages-v1.md) |
| `1204` | Interactive app state update v1 | Marmot app payload | [interactive-messages-v1.md](../features/interactive-messages-v1.md) |
```

State in `application-messages.md` that kind `9` may carry exactly one `interactive` tag while content remains fallback, and that `1203`/`1204` are hidden modifiers.

- [ ] **Step 3: Pin encoding and limits**

Add the RFC 8785 safe-integer profile to `canonical-encoding.md`. Define every closed object, tag position, numeric limit, fallback rule, and response policy in the feature document.

- [ ] **Step 4: Add literal conformance vectors**

Create valid vectors for minimal/all-block prompts, response, and app state; invalid vectors for duplicate IDs, absent input, field-group cycle, float, duplicate key, noncanonical JSON, oversize data, stale revision, and package mismatch. Each entry includes literal event fields, canonical preimage, event ID, and expected result.

- [ ] **Step 5: Verify and commit**

```bash
python3 -m json.tool foundation/fixtures/interactive-messages-v1.json >/dev/null
rg -n "Rust crate|database table|queue shape|retry worker|local API|test harness|\bengine\b|darkmatter" .
rg -n "CgkaEngine|PendingStateRef|drain_auto_publish|drain_auto_proposals|confirm_published|publish_failed" .
rg -n "Nostr kind|event id|relay URL|gift wrap|h tags?" protocol-core
git add features foundation layout.md
git commit -S -m "feat: specify interactive messages v1"
git log -1 --show-signature
```

### Task 2: Add shared Rust schemas and validation

**Repository:** `liamhelmer/mdk`

**Files:**
- Create: `crates/traits/src/interactive_messages.rs`
- Modify: `crates/traits/src/lib.rs`
- Test: `crates/traits/src/interactive_messages.rs`

**Interfaces:**
- Consumes: Task 1 schemas and fixtures.
- Produces: `InteractiveEnvelope`, block/action/value enums, response/app-update records, parsers, encoders, and validators.

- [ ] **Step 1: Write failing parser tests**

Add fixture-driven tests plus:

```rust
#[test]
fn malformed_tag_preserves_chat_fallback() {
    let event = chat_with_interactive_tag("Readable fallback", "not-base64");
    assert!(parse_interactive_prompt(&event).is_err());
    assert_eq!(event.content, "Readable fallback");
}

#[test]
fn duplicate_keys_floats_and_noncanonical_json_fail() {
    for bytes in [
        br#"{"version":1,"version":1}"#.as_slice(),
        br#"{"protocol":"marmot-interactive","version":1.0}"#.as_slice(),
        br#"{"version":1,"protocol":"marmot-interactive"}"#.as_slice(),
    ] {
        assert!(decode_canonical_envelope(bytes).is_err());
    }
}
```

- [ ] **Step 2: Confirm failure**

```bash
cargo test -p cgka-traits interactive_messages -- --nocapture
```

Expected: compile failure because the module is absent.

- [ ] **Step 3: Implement bounded canonical decoding**

Detect duplicate keys before Serde mapping, require RFC 8785 byte equality, traverse for safe integers, decode unpadded base64url, and validate exact tag shapes. Define concrete errors `InvalidKind`, `InvalidTags`, `InvalidBase64`, `InvalidUtf8`, `DuplicateJsonKey`, `NonCanonicalJson`, `LimitExceeded`, `InvalidSchema`, `InvalidReference`, and `Expired`.

- [ ] **Step 4: Implement the closed schema**

Use internally tagged Serde enums and `deny_unknown_fields`. Validate unique IDs, one-level field groups, no cycles, valid action-input references, choice cardinality, fallbacks, and extension declarations. Define `PerSenderLatest`, `PerSenderOnce`, `SingleAccept`, and `Open`.

- [ ] **Step 5: Implement response/app-state validation**

Parse kinds `1203`/`1204`; bind response to exact prompt, interaction, revision, action, values, expiry, and artifact digest. Preserve the app payload as bounded opaque UTF-8 JSON bytes after parsing exactly one value.

- [ ] **Step 6: Add boundary/adversarial tests**

Test 65,536/65,537 bytes, 64/65 blocks, 100/101 options, 16,384/16,385 text bytes, missing input, cycle, stale revision, unknown action, expiry, malformed app JSON, and duplicate IDs.

- [ ] **Step 7: Pass tests and commit**

```bash
cargo test -p cgka-traits interactive_messages
cargo fmt --all --check
git add crates/traits/src/interactive_messages.rs crates/traits/src/lib.rs
git commit -S -m "feat: validate interactive message payloads"
git log -1 --show-signature
```

### Task 3: Add MDK send intents and runtime commands

**Repository:** `liamhelmer/mdk`

**Files:**
- Modify: `crates/marmot-app/src/messages/intents.rs`
- Modify: `crates/marmot-app/src/runtime/commands.rs`
- Modify: `crates/marmot-app/src/runtime/mod.rs`
- Modify: `crates/marmot-app/src/client/mod.rs`
- Modify: `crates/marmot-app/src/client/audit.rs`
- Modify: `crates/marmot-app/src/lib.rs`
- Test: `crates/marmot-app/src/runtime/tests.rs`
- Test: `crates/marmot-app/src/tests.rs`

**Interfaces:**
- Consumes: Task 2 typed parsers and encoders.
- Produces: `send_interactive_prompt`, `respond_to_interaction`, and `send_interactive_app_update`, each returning `SendSummary`.

- [ ] **Step 1: Write failing intent tests**

Assert a prompt emits kind `9` with unchanged fallback and one canonical tag; a response emits kind `1203` with exact `e`, `interactive`, and `action` tags; app state emits kind `1204` with exact target, instance, package, and sequence tags.

- [ ] **Step 2: Confirm failure**

```bash
cargo test -p marmot-app interactive_intent -- --nocapture
```

Expected: absent intent variants fail compilation.

- [ ] **Step 3: Add typed intents**

Add these variants and route them through the single event builder:

```rust
InteractivePrompt {
    fallback: String,
    envelope: InteractiveEnvelope,
},
InteractiveResponse {
    prompt_event_id: String,
    interaction_id: String,
    revision: u64,
    response: InteractiveResponse,
},
InteractiveAppUpdate {
    prompt_event_id: String,
    interaction_id: String,
    revision: u64,
    app_instance_id: String,
    package_sha256: String,
    update_seq: u64,
    payload: Vec<u8>,
},
```

Reserve kinds `1203`/`1204` so generic custom events cannot forge them.

- [ ] **Step 4: Add runtime preflight**

Load the target row and require a current valid projection. Reject stale, expired, deleted, invalidated, unknown-action, and invalid-value requests before sending.

- [ ] **Step 5: Add privacy-safe audit mappings**

Use action names matching the three methods. Record bounded counts only; never text, values, IDs, hashes, or payload bytes.

- [ ] **Step 6: Test rejection and round-trip**

A recording transport proves invalid requests never send. Parse valid emitted events with Task 2 and verify canonical IDs.

- [ ] **Step 7: Pass and commit**

```bash
cargo test -p marmot-app interactive
git add crates/marmot-app/src
git commit -S -m "feat: send interactive message events"
git log -1 --show-signature
```

### Task 4: Materialize projections and hide modifiers

**Repository:** `liamhelmer/mdk`

**Files:**
- Create: `crates/storage-sqlite/src/migrations/0091_interactive_message_edges.rs`
- Modify: `crates/storage-sqlite/src/migrations.rs`
- Modify: `crates/storage-sqlite/src/timeline.rs`
- Modify: `crates/storage-sqlite/src/timeline/tests.rs`

**Interfaces:**
- Consumes: Task 2 validators.
- Produces: `TimelineMessageRecord.interactive`, hidden edges, and deterministic prompt reprojection.

- [ ] **Step 1: Write failing visibility/fallback tests**

Insert valid/malformed prompts, a response, and app state. Assert only prompts form rows; malformed prompts retain plaintext with no projection.

- [ ] **Step 2: Write failing selection tests**

Cover all policies, out-of-arrival order, equal timestamps with ID tie-break, stale revision, expiry, unknown action, invalid value, deletion, invalidation, and retention pruning.

- [ ] **Step 3: Confirm failure**

```bash
cargo test -p storage-sqlite interactive -- --nocapture
```

- [ ] **Step 4: Add migration 0091**

Follow `0090_poll_response_edges.rs`: index valid target edges for `1203`/`1204`, delete obsolete modifier rows, and prove rerunning is a no-op.

- [ ] **Step 5: Project prompt state**

Parse kind-`9` tagged rows, bound modifier work, select responses per Task 1, and reproject prompts without unread or activity advancement.

- [ ] **Step 6: Pass suites and commit**

```bash
cargo test -p storage-sqlite interactive
cargo test -p storage-sqlite migrations
git add crates/storage-sqlite/src
git commit -S -m "feat: project interactive message responses"
git log -1 --show-signature
```

### Task 5: Export UniFFI and C bindings

**Repository:** `liamhelmer/mdk`

**Files:**
- Create: `crates/marmot-uniffi/src/conversions/interactive_messages.rs`
- Modify: `crates/marmot-uniffi/src/conversions/mod.rs`
- Modify: `crates/marmot-uniffi/src/conversions/timeline.rs`
- Modify: `crates/marmot-uniffi/src/commands/message.rs`
- Modify: `crates/marmot-uniffi/API-REFERENCE.md`
- Create: `crates/marmot-c/src/types/interactive_messages.rs`
- Modify: `crates/marmot-c/src/types/mod.rs`
- Modify: `crates/marmot-c/src/types/timeline.rs`
- Modify: `crates/marmot-c/src/commands.rs`
- Modify: `crates/marmot-c/API-REFERENCE.md`
- Modify: `crates/marmot-c/CHANGELOG.md`
- Regenerate: `crates/marmot-c/include/marmot.h`

**Interfaces:**
- Consumes: Tasks 3–4 runtime/projection.
- Produces: typed FFI unions, `TimelineMessageRecordFfi.interactive`, and three commands.

- [ ] **Step 1: Write failing round-trip tests**

Build every block/action variant and assert order, IDs, fallbacks, policy, current response, lifecycle, and unsupported-extension data survive.

- [ ] **Step 2: Define typed FFI records**

Use payload enums and dedicated records. Define values:

```rust
pub enum InteractiveValueFfi {
    Text { value: String },
    Choices { option_ids: Vec<String> },
    Confirmed { value: bool },
}
```

Do not expose unvalidated envelope JSON as the primary API.

- [ ] **Step 3: Export UniFFI commands**

Add the three Task 3 methods. Use typed prompt/response records; accept app-update JSON as `String` and convert at the boundary.

- [ ] **Step 4: Mirror C records and commands**

Use deep-free-safe mirrors, borrowed inputs, preflight discriminant/out-pointer checks, and regenerated headers.

- [ ] **Step 5: Update docs and parity**

```bash
just binding-docs-update
just binding-docs-gate
just c-parity-gate
```

Complete prose for lifecycle, bounds, fallback, modifiers, and ownership.

- [ ] **Step 6: Test and commit**

```bash
cargo test -p marmot-uniffi interactive
cargo test -p marmot-c --features alloc-audit interactive
just c-header
git diff --exit-code crates/marmot-c/include/marmot.h
just c-smoke
just uniffi-projections-smoke swift
git add crates/marmot-uniffi crates/marmot-c
git commit -S -m "feat: expose interactive messages in app bindings"
git log -1 --show-signature
```

### Task 6: Verify and open the MDK PR

**Repository:** `liamhelmer/mdk`

**Files:** Modify only files required by failures in Tasks 2–5.

**Interfaces:**
- Consumes: completed MDK implementation.
- Produces: a green signed branch ready for review and release.

- [ ] **Step 1: Run targeted suites**

```bash
cargo test -p cgka-traits interactive_messages
cargo test -p marmot-app interactive
cargo test -p storage-sqlite interactive
cargo test -p marmot-uniffi interactive
cargo test -p marmot-c --features alloc-audit interactive
```

- [ ] **Step 2: Run repository gates**

```bash
just fast-ci
just binding-docs-gate
just c-parity-gate
```

- [ ] **Step 3: Verify signatures**

```bash
git log origin/master..HEAD --show-signature --format='%h %G? %s'
```

Expected: every commit reports `G`.

- [ ] **Step 4: Push and open the PR**

```bash
git push -u fork feature/interactive-messages-v1
gh pr create --repo marmot-protocol/mdk --base master --head liamhelmer:feature/interactive-messages-v1 --title "feat: add interactive message projections" --body "Implements bounded parsing, hidden modifiers, deterministic projection, and UniFFI/C APIs. Verified with fast-ci, targeted tests, documentation, and parity gates."
```

- [ ] **Step 5: Stop for merge/release authorization**

Report the PR URL. Do not publish a release or edit macOS pins until upstream merges and the user explicitly authorizes release.

### Task 7: Sync released MarmotKit and map projections

**Repository:** `liamhelmer/whitenoise-mac`

**Prerequisite:** MDK is merged and an authorized MarmotKit release contains that exact commit.

**Files:**
- Modify via generator: `Vendored/MarmotKit/Package.swift`
- Modify via generator: `Vendored/MarmotKit/Sources/MarmotKit/MarmotKit.swift`
- Modify via generator: `Vendored/MarmotKit/MARMOT_VERSION`
- Modify: `whitenoise-mac/Core/MarmotClient.swift`
- Modify: `whitenoise-macTests/Support/FakeMarmotRuntime.swift`
- Create: `whitenoise-mac/Models/InteractiveMessageModels.swift`
- Modify: `whitenoise-mac/Core/MarmotMapping.swift`
- Modify: `whitenoise-mac/Models/MessengerModels.swift`
- Create: `whitenoise-macTests/InteractiveMessageMappingTests.swift`
- Modify: `whitenoise-macTests/Support/TestFixtures.swift`

**Interfaces:**
- Consumes: published Task 5 FFI.
- Produces: immutable app-owned `InteractiveMessage` models and `MessageItem.interactive`.

- [ ] **Step 1: Start clean and sync generated bindings**

```bash
git fetch origin master
git switch -c feature/interactive-messages-v1 origin/master
marmotkit_tag="$(gh release list --repo marmot-protocol/mdk --limit 100 --json tagName,isDraft,publishedAt --jq '[.[] | select(.isDraft == false and (.tagName | startswith("marmotkit-")))] | sort_by(.publishedAt) | last | .tagName')"
test -n "$marmotkit_tag"
just sync-bindings "$marmotkit_tag"
```

Confirm `MARMOT_VERSION` contains the exact merged MDK SHA before continuing. Never hand-edit generated Swift or checksums.

- [ ] **Step 2: Write failing mapping tests**

Build an FFI projection containing every block/action and assert stable order, IDs, policy, response, lifecycle, graphics alt text, and unsupported app fallback map to app-owned `Sendable` values.

- [ ] **Step 3: Confirm failure and test selection**

```bash
xcodebuild test -scheme whitenoise-mac -configuration Debug -destination 'platform=macOS,arch=arm64' -testPlan PR CODE_SIGNING_ALLOWED=NO -only-testing:'whitenoise-macTests/InteractiveMessageMappingTests/mapsAllInteractiveBlocks()'
```

Expected: compile failure because mapping is absent. Later passing runs must report exactly one executed test.

- [ ] **Step 4: Add projection models and mapping**

Define immutable enums/structs in `InteractiveMessageModels.swift`; add `let interactive: InteractiveMessage?` to `MessageItem`; map validated FFI only. Never parse raw envelope JSON in Swift.

- [ ] **Step 5: Extend runtime and fake**

Add typed `respondToInteraction` to `MarmotRuntime`, forward through `MarmotClient`, and record it in `FakeMarmotRuntime`. Do not add `WorkspaceState` state or methods.

- [ ] **Step 6: Verify and commit**

```bash
xcodebuild -scheme whitenoise-mac -configuration Debug build-for-testing CODE_SIGNING_ALLOWED=NO
just sanity
git add Vendored/MarmotKit whitenoise-mac/Core/MarmotClient.swift whitenoise-mac/Core/MarmotMapping.swift whitenoise-mac/Models/MessengerModels.swift whitenoise-mac/Models/InteractiveMessageModels.swift whitenoise-macTests/Support/FakeMarmotRuntime.swift whitenoise-macTests/Support/TestFixtures.swift whitenoise-macTests/InteractiveMessageMappingTests.swift
git commit -S -m "feat: map Marmot interactive messages"
git log -1 --show-signature
```

### Task 8: Build the isolated feature model and response flow

**Repository:** `liamhelmer/whitenoise-mac`

**Files:**
- Create: `whitenoise-mac/Features/InteractiveMessages/InteractiveMessageViewModel.swift`
- Create: `whitenoise-mac/Features/InteractiveMessages/InteractiveMessageResponder.swift`
- Create: `whitenoise-macTests/InteractiveMessageViewModelTests.swift`

**Interfaces:**
- Consumes: Task 7 models/runtime.
- Produces: `@MainActor @Observable final class InteractiveMessageViewModel` with inputs, validation, submission state, and `submit(actionID:)`.

- [ ] **Step 1: Write failing tests**

Test initial values, required text, choice cardinality, confirmation, unknown action, missing input, expiry, duplicate taps, success, safe error state, and unsupported projection disabling all actions.

- [ ] **Step 2: Confirm failure**

```bash
xcodebuild test -scheme whitenoise-mac -configuration Debug -destination 'platform=macOS,arch=arm64' -testPlan PR CODE_SIGNING_ALLOWED=NO -only-testing:'whitenoise-macTests/InteractiveMessageViewModelTests'
```

- [ ] **Step 3: Define responder boundary**

```swift
nonisolated protocol InteractiveMessageResponding: Sendable {
    func respond(
        accountRef: String,
        groupID: String,
        promptEventID: String,
        interactionID: String,
        revision: UInt64,
        actionID: String,
        values: [String: InteractiveValue]
    ) async throws
}
```

Implement a thin Marmot adapter and a recording test fake.

- [ ] **Step 4: Implement view model**

The initializer takes projection, account/group/prompt IDs, responder, and clock. Store only ephemeral values/errors/submission state. Validate for immediate feedback, let MDK preflight authoritatively, prevent concurrent submission, and ignore completion after cancellation.

- [ ] **Step 5: Pass and commit**

Confirm the test log reports a nonzero expected count, then:

```bash
git add whitenoise-mac/Features/InteractiveMessages whitenoise-macTests/InteractiveMessageViewModelTests.swift
git commit -S -m "feat: add interactive response model"
git log -1 --show-signature
```

### Task 9: Render native blocks, graphics, and fallback

**Repository:** `liamhelmer/whitenoise-mac`

**Files:**
- Create: `whitenoise-mac/Features/InteractiveMessages/InteractiveMessageView.swift`
- Create: `whitenoise-mac/Features/InteractiveMessages/InteractiveBlockViews.swift`
- Create: `whitenoise-mac/Features/InteractiveMessages/InteractiveGraphicViews.swift`
- Create: `whitenoise-mac/Features/InteractiveMessages/InteractiveActionBar.swift`
- Modify: `whitenoise-mac/Views/MessageMediaViews.swift`
- Modify through Xcode catalog editor: `whitenoise-mac/Localizable.xcstrings`
- Create: `whitenoise-macTests/InteractiveMessagePresentationTests.swift`

**Interfaces:**
- Consumes: Task 8 view model and existing verified media services.
- Produces: native Level 1 UI and accessible graphics/app fallbacks.

- [ ] **Step 1: Write failing presentation-contract tests**

Assert all ten blocks are covered; the root view requires a model initializer; new feature views do not read `WorkspaceState`; every new view file has `#Preview`; missing graphics show alt text; unsupported app shows fallback and no launch action.

- [ ] **Step 2: Confirm failure**

```bash
xcodebuild test -scheme whitenoise-mac -configuration Debug -destination 'platform=macOS,arch=arm64' -testPlan PR CODE_SIGNING_ALLOWED=NO -only-testing:'whitenoise-macTests/InteractiveMessagePresentationTests'
```

- [ ] **Step 3: Implement native view structs**

Use one stored-`body` `View` struct per block family, native controls, adjacent validation errors, semantic roles, keyboard order, and accessible labels. Reuse the existing Markdown display pipeline.

- [ ] **Step 4: Implement graphics safely**

Reuse verified attachment loading for images. For Mermaid show its verified fallback image or alt text; do not add JavaScript. Decode SVG only through the safe image path, otherwise show PNG/text fallback. Never inject SVG into HTML.

- [ ] **Step 5: Integrate the bubble**

Render the feature view when `message.interactive` is valid; otherwise use the existing Markdown fallback. Construct the model with explicit account/group/prompt/responder dependencies and no new workspace state.

- [ ] **Step 6: Add previews/localization**

Add previews for a form, approval artifact, missing diagram, and unsupported app. Edit the String Catalog through Xcode, then:

```bash
just locales
```

- [ ] **Step 7: Pass and commit**

```bash
xcodebuild test -scheme whitenoise-mac -configuration Debug -destination 'platform=macOS,arch=arm64' -testPlan PR CODE_SIGNING_ALLOWED=NO -only-testing:'whitenoise-macTests/InteractiveMessagePresentationTests'
git add whitenoise-mac/Features/InteractiveMessages whitenoise-mac/Views/MessageMediaViews.swift whitenoise-mac/Localizable.xcstrings whitenoise-macTests/InteractiveMessagePresentationTests.swift
git commit -S -m "feat: render native interactive messages"
git log -1 --show-signature
```

### Task 10: Verify and open the macOS PR

**Repository:** `liamhelmer/whitenoise-mac`

**Files:** Modify only files required by Tasks 7–9 verification failures.

**Interfaces:**
- Consumes: complete Level 1 implementation.
- Produces: signed upstream macOS PR.

- [ ] **Step 1: Build app and tests**

```bash
xcodebuild -scheme whitenoise-mac -configuration Debug build CODE_SIGNING_ALLOWED=NO
xcodebuild -scheme whitenoise-mac -configuration Debug build-for-testing CODE_SIGNING_ALLOWED=NO
```

- [ ] **Step 2: Run the complete PR plan**

```bash
xcodebuild test-without-building -scheme whitenoise-mac -configuration Debug -destination 'platform=macOS,arch=arm64' -testPlan PR CODE_SIGNING_ALLOWED=NO | tee /tmp/whitenoise-interactive-tests.log
rg 'Executed [0-9]+ test' /tmp/whitenoise-interactive-tests.log
```

Expected: zero exit and nonzero executed count.

- [ ] **Step 3: Run precommit**

```bash
just precommit
```

Commit coherent verification fixes with signed commits.

- [ ] **Step 4: Validate one app instance**

Terminate existing `White Noise`, launch one fresh build without `open -n`, and verify fallback, choice submission, expired action, and app fallback. Quit afterward unless asked to leave it running.

- [ ] **Step 5: Verify signatures and open PR**

```bash
git log origin/master..HEAD --show-signature --format='%h %G? %s'
git push -u fork feature/interactive-messages-v1
gh pr create --repo marmot-protocol/whitenoise-mac --base master --head liamhelmer:feature/interactive-messages-v1 --title "feat: render interactive messages" --body "Implements native Level 1 interactive messages with fallback, typed response submission, graphics fallback, and unsupported interactive_app presentation. Verified with build, full PR tests, precommit, and single-instance manual checks."
```

Expected: every commit reports `G`; the PR remains unmerged.



Expected: JSON succeeds, new links resolve, prohibited implementation details are absent, and the signature is good.

- [ ] **Step 6: Push and open the protocol PR**

```bash
git push -u fork feature/interactive-messages-v1
gh pr create --repo marmot-protocol/marmot --base master --head liamhelmer:feature/interactive-messages-v1 --title "feat: specify interactive messages v1" --body "Defines the v1 event profile, bounds, selection rules, and conformance vectors."
```
