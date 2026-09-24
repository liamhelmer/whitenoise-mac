# Cross-Platform Marmot Interactive Messages

**Status:** Approved design
**Date:** 2026-09-23
**Target platforms:** Android, iOS, macOS, Linux
**Protocol owners:** `marmot-protocol/marmot` and `marmot-protocol/mdk`

## 1. Purpose

Define a portable interactive-message system for Marmot conversations. The
first implementation supports native questions, choices, forms, approvals,
status, artifacts, images, and diagrams. A later extension hosts offline
WebXDC-compatible applications through an `interactive_app` block.

The design serves agent-assisted conversations such as iterative brainstorming
and proposal review. It also provides a presentation and intent-collection
surface for Heterodyne Workspace operations without making chat UI state an
authority source.

Success means that Android, iOS, macOS, and Linux can receive the same Marmot
event, render equivalent native controls, submit equivalent response events,
and derive the same effective state. Existing Linux clients must retain a
readable message even before they adopt structured rendering.

## 2. Existing Contracts

This design extends, rather than replaces, the existing Marmot application
payload model:

- A Marmot app payload is an unsigned Nostr-shaped event carried inside an MLS
  application message.
- Kind `9` is an ordinary chat message. Optional features may attach additional
  semantics with feature-owned tags.
- Unknown inner event kinds remain structurally valid and may be ignored at the
  application layer.
- MLS authenticates the sender account. The canonical Marmot app-event ID binds
  `pubkey`, `created_at`, `kind`, `tags`, and `content`.
- Kinds `1200` through `1202` are already reserved for agent streaming,
  activity, and operation experiments. Interactive messages must not redefine
  them.
- NIP-88 polls are a precedent for MDK-owned parsing, projection, response
  selection, and FFI exposure, but their voting model is not a general form or
  approval protocol.

Linux currently transports WebXDC state through ordinary text beginning with
`wnxdc1:`. That convention is a compatibility workaround, not a normative
Marmot wire format. New implementations must not emit it.

## 3. Scope

### 3.1 In scope

- A versioned interactive envelope attached to a readable chat message.
- A bounded baseline vocabulary of native blocks and actions.
- Immutable response events and deterministic projected state.
- Static images, passive SVG, and Mermaid diagrams with accessible fallbacks.
- Artifact references, including Heterodyne objects.
- Progressive client capability levels.
- A future `interactive_app` block compatible with existing `.xdc` packages.
- A migration path from Linux's `wnxdc1:` state messages.
- Shared MDK validation, construction, persistence, and projection.
- Cross-platform fixtures and conformance tests.

### 3.2 Out of scope

- A general-purpose UI layout or styling language.
- Arbitrary scripts in baseline native messages.
- Agent execution, model selection, or tool orchestration.
- Treating conversational approval as Heterodyne authorization.
- Replacing MLS, Marmot ordering, encrypted media, or Radicle.
- Globally serialized voting or consensus.
- Direct network access from interactive applications.
- Making all clients implement a browser runtime.

## 4. Capability Levels

Clients implement the feature progressively:

| Level | Name | Required behavior |
| --- | --- | --- |
| 0 | Fallback | Render the ordinary kind-`9` Markdown content. |
| 1 | Native interactions | Render the standard block vocabulary and submit typed responses. |
| 2 | Interactive applications | Run verified `.xdc` packages in a restricted host and exchange state updates and declared actions. |

Level 0 is sufficient for conversation membership. A group must not require a
new MLS app component merely to send or receive durable interactive messages.
Interactive controls are a progressive application-layer enhancement.

## 5. Architecture

```text
Marmot kind-9 app event
├── content: complete Markdown fallback
└── interactive tag: versioned canonical envelope
    ├── native blocks
    ├── declared actions
    ├── response policy
    └── optional interactive_app block
        └── content-addressed encrypted .xdc attachment

Modifier events
├── interactive response
└── interactive-app state update
```

The logical units are:

1. **Protocol document:** Owns the event shapes, schemas, limits, selection
   rules, and security invariants.
2. **MDK interactive-message module:** Constructs and validates events,
   persists modifiers, and publishes typed projections over C and UniFFI.
3. **Native renderer:** Maps validated blocks to SwiftUI, Jetpack Compose, or
   Linux native widgets and returns typed values to MDK.
4. **Interactive-app host:** Loads verified `.xdc` packages and mediates their
   state and action bridge. This is not required for the first implementation.

## 6. Marmot Event Profile

### 6.1 Prompt event

An interactive prompt is one kind-`9` Marmot app event:

```text
kind: 9
content: complete human-readable Markdown fallback
tags:
  ["interactive", "1", base64url(canonical_envelope_json)]
```

The `interactive` tag must occur exactly once for an interactive prompt. Its
third value is unpadded base64url of UTF-8 canonical JSON. A malformed or
unsupported tag never invalidates the surrounding kind-`9` chat semantics;
the receiver renders `content` normally and disables structured interaction.

The fallback must be self-contained. It must state the question or proposal,
enumerate relevant choices, and describe how an unsupported client can reply
in ordinary text. It must not tell the reader that invisible controls are the
only way to respond.

The envelope and fallback share one authenticated app-event ID. This prevents
separation, reordering, and substitution between presentation forms.

### 6.2 Canonical feature JSON

Envelope, response, and state-update wrapper JSON uses RFC 8785 JSON
Canonicalization Scheme encoded as UTF-8. Protocol integers are nonnegative and
no greater than `9,007,199,254,740,991`, so every target language can represent
them exactly in its interoperable JSON number model. Protocol schemas do not
permit floating-point values. Decoders reject duplicate member names before
canonicalization and reject input whose bytes are not already canonical.

Opaque WebXDC application payloads are the sole exception: the host preserves
their original bounded UTF-8 JSON bytes inside a base64url string in the
canonical state-update wrapper. MDK authenticates and orders those bytes but
does not reinterpret or canonicalize the application's object.

### 6.3 Interactive response event

The Marmot feature allocates kind `1203` for an interactive response:

```text
kind: 1203
tags:
  ["e", prompt_event_id]
  ["interactive", "1", interaction_id, decimal_revision]
  ["action", action_id]
content: canonical response JSON
```

Kind `1203` is a modifier, not a transcript row. Updated MDK clients project it
onto the referenced prompt. An older client may show it as an unsupported event;
the prompt itself remains a readable kind-`9` message.

The response binds to the exact prompt app-event ID, interaction ID, revision,
and declared action. MDK rejects it from the effective projection if any binding
does not match. Structurally valid but ineffective events remain available to
diagnostics and history policy.

### 6.4 Interactive-app state event

The Marmot feature allocates kind `1204` for an interactive-app state update:

```text
kind: 1204
tags:
  ["e", prompt_event_id]
  ["interactive", "1", interaction_id, decimal_revision]
  ["app-instance", app_instance_id]
  ["package", plaintext_sha256_hex]
  ["update-seq", unsigned_decimal_sender_sequence]
content: canonical state-update JSON
```

The state-update content has this exact shape:

```json
{
  "version": 1,
  "payload": "<unpadded base64url of the app's UTF-8 JSON bytes>"
}
```

The sending host obtains the payload bytes from the WebXDC bridge's JSON
serialization of the value passed to `sendUpdate`. A receiver decodes the bytes,
parses one JSON value, and delivers that value to `setUpdateListener`. The value
may use JSON numbers permitted by the WebXDC runtime; it has no protocol meaning
to MDK.

Kind `1204` is a modifier and never a chat row. It is defined with the
`interactive_app` extension even though the numeric allocation is reserved in
the initial Marmot feature document. Baseline clients may store and ignore it.

The sequence is monotonic per authenticated sender and app instance. It does
not imply a total order across senders. Duplicate event IDs are idempotent;
duplicate or decreasing sender sequences do not reapply state.

### 6.5 Revisions

A revision is a new kind-`9` prompt event with the same `interaction_id`, a
higher integer `revision`, and a `replaces_event_id` in its envelope. A valid
revision must:

- be authored by the same authenticated Marmot account as revision 1;
- reference the immediately preceding effective prompt event;
- increase `revision` by exactly one; and
- contain a complete replacement envelope and fallback.

Responses bind to one exact revision. They are never silently reinterpreted
against a later revision. A client may visually collapse replaced prompts but
must retain immutable event history.

### 6.6 Future carrier optimization

A future MDK application-event API may avoid base64 overhead while preserving
the same logical envelope. Any alternate carrier requires a Marmot feature
revision and must retain a complete readable kind-`9` fallback. It cannot be a
client-local encoding variation.

## 7. Envelope Schema

The decoded prompt envelope has these members:

```json
{
  "protocol": "marmot-interactive",
  "version": 1,
  "interaction_id": "0195...",
  "revision": 1,
  "replaces_event_id": null,
  "response_policy": "per_sender_latest",
  "expires_at": null,
  "required_extensions": [],
  "optional_extensions": [],
  "blocks": [],
  "actions": []
}
```

Rules:

- `protocol` is exactly `marmot-interactive`.
- `version` is the integer `1`.
- `interaction_id` is 16 random bytes encoded as 32 lowercase hexadecimal
  characters. It is stable across revisions.
- `revision` begins at `1`.
- `replaces_event_id` is null for revision 1 and a lowercase 64-character
  Marmot app-event ID for later revisions.
- `expires_at` is null or Unix seconds. Expiry prevents new effective actions;
  it does not hide prior content.
- Every block and action ID is unique within its namespace and consists of 1 to
  64 ASCII letters, digits, `_`, `-`, or `.`.
- Unknown top-level members are rejected in version 1. Extensions place their
  data under their registered block or action type rather than adding ambient
  top-level fields.
- JSON numbers are integers. Floating-point values are forbidden.

## 8. Baseline Native Blocks

All Level 1 clients implement these blocks:

| Block | Purpose | Essential fields |
| --- | --- | --- |
| `markdown` | Explanatory formatted content | `id`, `text` |
| `text_input` | Single- or multiline text | `id`, `label`, `multiline`, `required`, `min_length`, `max_length`, optional `initial` |
| `choice` | Single or multiple selection | `id`, `label`, `selection`, `required`, ordered `options` |
| `confirmation` | Explicit acknowledgment | `id`, `label`, `required`, `statement` |
| `field_group` | Ordered semantic grouping | `id`, optional `label`, child block IDs |
| `divider` | Semantic separation | `id` |
| `status` | Informational state | `id`, `status`, `text` |
| `artifact` | Typed content-addressed object | `id`, `artifact_type`, `digest`, `media_type`, attachment reference, `summary` |
| `image` | Static visual media | `id`, attachment reference, `media_type`, `alt`, optional `caption` and dimensions |
| `diagram` | Portable diagram source | `id`, `notation`, `source`, renderer profile, required visual or textual fallback |

`field_group` may contain input blocks but may not recursively contain another
`field_group`. Blocks define semantic order only. They do not define arbitrary
grids, coordinates, fonts, colors, or platform-specific controls.

Text fields never request or accept passwords, private keys, recovery phrases,
authentication tokens, or other secret-input semantics. A message cannot mark
an input as trusted merely by naming it accordingly.

## 9. Graphics

### 9.1 Images

An `image` references Marmot encrypted media by its plaintext and ciphertext
hashes and carries required alt text. Capable clients verify the media reference
through MDK before decoding it. Opening an image is a local presentation action,
not a protocol response.

### 9.2 Mermaid

A Mermaid `diagram` includes source, a pinned renderer profile such as
`mermaid@11`, and a required fallback image or complete textual description.
Rendering is optional at Level 1; displaying the fallback is conforming.
Mermaid output is presentation, not canonical protocol state.

### 9.3 SVG

SVG is a referenced encrypted-media attachment, never inline envelope markup.
Hosts treat it as passive image content and disable scripts, event handlers,
external resources, navigation, embedded HTML, and network access. A client
that cannot enforce this profile uses the required PNG or textual fallback.

Interactive diagrams and canvases belong in `interactive_app`, not SVG or
Mermaid extensions.

## 10. Actions and Responses

### 10.1 Baseline actions

| Action | Meaning |
| --- | --- |
| `submit` | Return values from declared input blocks. |
| `approve` | Record explicit approval of the displayed proposal and bound artifact digests. |
| `reject` | Reject the proposal, optionally submitting a declared reason input. |
| `cancel` | Withdraw or end the responding sender's participation. |
| `open` | Ask the host to open a declared artifact through a safe local capability. |

An action declares its stable ID, type, label, input block IDs, semantic intent,
confirmation requirement, and optional opaque context. Opaque context is
returned unchanged and has no authority semantics.

The response JSON is:

```json
{
  "version": 1,
  "action_id": "continue",
  "intent": "brainstorm.answer",
  "values": {
    "approach": ["native"]
  },
  "context": null,
  "artifact_digests": []
}
```

MDK validates value types and bounds against the exact referenced prompt before
publishing locally and again before selecting a received response as effective.

### 10.2 Response policies

- `per_sender_latest`: each sender may revise; select the greatest valid
  `(created_at, canonical event id)` for that sender.
- `per_sender_once`: select the least valid `(created_at, canonical event id)`
  for that sender and ignore later responses.
- `single_accept`: select the least valid accepted response globally by
  `(created_at, canonical event id)` as a coordination projection.
- `open`: retain all valid responses in deterministic order.

`single_accept` is not consensus. A high-stakes operation must resolve conflicts
under its authoritative external protocol.

## 11. Lifecycle and Projection

```text
open ──effective response──▶ answered
  │                            │
  ├──expiry──────────────────▶ expired
  ├──cancel response─────────▶ cancelled-for-sender
  └──valid new revision──────▶ replaced
```

MDK applies this pipeline:

1. Authenticate and structurally accept the Marmot app event.
2. Decode the feature tag and canonical JSON within fixed resource limits.
3. Validate the complete prompt, response, or update schema.
4. Bind modifiers to the exact target, interaction ID, revision, and author.
5. Select effective modifiers deterministically.
6. Publish a typed projection and update it when relevant events change through
   convergence, deletion, moderation, or retention.

Malformed structured data never hides valid kind-`9` fallback content.
Deletion, invalidation, moderation, and disappearing-message retention follow
the existing MDK lifecycle. When a target prompt ceases to be presentable, its
interactive projection and decrypted app resources cease to be presentable too.

## 12. `interactive_app` Extension

### 12.1 Block

The extension adds this optional block:

```json
{
  "id": "workspace-map",
  "type": "interactive_app",
  "package": {
    "attachment": "sha256:...",
    "media_type": "application/vnd.webxdc+zip",
    "plaintext_sha256": "...",
    "size": 184320
  },
  "profile": "webxdc-1",
  "fallback": {
    "attachment": "sha256:...",
    "media_type": "image/png",
    "alt": "Workspace dependency map"
  },
  "capabilities": ["state_updates", "submit_action"]
}
```

Unsupported clients render its fallback. Support for `interactive_app` is never
required to understand the other blocks in the same prompt.

### 12.2 Package compatibility

Profile `webxdc-1` supports Linux's current package shape:

- ZIP archive with `index.html`;
- optional `manifest.toml`, name, icon, and static resources;
- `window.webxdc.sendUpdate`;
- `window.webxdc.setUpdateListener`;
- offline execution; and
- ephemeral web storage by default.

Existing packages should require no change unless they rely on currently stubbed
or unsafe APIs.

### 12.3 Host bridge

The host exposes two conceptually separate channels:

- `sendUpdate(update)`: publishes bounded collaborative state through kind
  `1204`.
- `submitAction(actionId, values)`: requests one action declared by the parent
  envelope. The host validates values and may show native confirmation before
  asking MDK to publish kind `1203`.

`sendToChat`, realtime peer channels, and ambient file import are not part of
the first profile. File import may be added only as a user-initiated host
capability with explicit package declaration.

### 12.4 Update delivery

Each app instance is bound to the parent prompt event and package plaintext
hash. The host replays valid updates in deterministic order
`(created_at, canonical event id)` after enforcing per-sender monotonically
increasing sequence values. Apps must tolerate concurrent senders, replay, and
missing updates. Marmot does not promise a global sequencer.

### 12.5 Sandbox

Every host must enforce:

- no network access or external navigation;
- no popups or programmatic downloads;
- no ambient filesystem, clipboard, camera, microphone, location, notification,
  credential, or account access;
- ephemeral cookies and website data;
- ZIP path, MIME, file-count, compressed-size, and extracted-size validation;
- bounded update size, CPU time, memory, and storage;
- visible app identity, sender identity, and exit control;
- user initiation for imports and external opening; and
- package-hash binding on every state update.

A sandbox failure terminates the runtime and returns to the static fallback.

## 13. Linux Migration

Linux retains its existing WebKitGTK host and places it behind the shared
`interactive_app` block interface. Migration proceeds as follows:

1. Adopt MDK projections for prompts and responses.
2. Render the baseline native blocks.
3. Adapt the existing WebXDC launcher to consume the validated package reference.
4. Publish new app updates as kind `1204` instead of `wnxdc1:` chat text.
5. Retain a read-only parser for legacy `wnxdc1:` updates associated with old
   sessions.
6. Never translate a legacy update into a newly published legacy message.

No extensive rewrite of the WebKitGTK process boundary is required. The main
change is replacing its chat-text transport adapter with MDK's typed projection
and send APIs.

## 14. Heterodyne Boundary

Interactive messages present proposals and collect authenticated conversational
intent. They are not Heterodyne authority.

An `artifact` may reference a canonical Workspace proposal by media type,
attachment, and digest. An approval response binds the prompt event ID,
interaction revision, action ID, and artifact digest. Before any Workspace
operation, the host must independently:

1. retrieve and verify the exact artifact;
2. show trusted native confirmation identifying the authenticated requester,
   signing identity, target, and consequence;
3. validate Workspace schema, freshness, capabilities, and policy; and
4. create or sign the canonical Heterodyne object through its authoritative
   implementation.

Radicle-backed Workspace history remains authoritative. Marmot is the private
coordination and carriage layer.

## 15. Security Invariants

- A message cannot impersonate native security, account, permission, or signing
  UI.
- Sender identity is always visible for an actionable prompt.
- Structured content cannot suppress its fallback or cause automatic action.
- Default values are never submitted without a user action.
- An action cannot reference an input absent from the same revision.
- Unknown required semantics disable affected actions.
- Opaque context and semantic intent names never confer authority.
- Interactive responses are ordinary authenticated statements by their Marmot
  sender, not signatures over external protocols.
- Privileged actions require a trusted host confirmation outside untrusted
  message content.
- Web content cannot directly access MDK, MLS secrets, signing keys, account
  credentials, or Heterodyne capabilities.
- Graphics are passive unless hosted by the sandboxed `interactive_app` profile.

## 16. Resource Limits

Version 1 pins these decoded limits:

| Resource | Limit |
| --- | ---: |
| Envelope JSON | 65,536 UTF-8 bytes |
| Response JSON | 65,536 UTF-8 bytes |
| State-update JSON | 131,072 UTF-8 bytes |
| Blocks | 64 |
| Actions | 32 |
| Total Markdown | 32,768 UTF-8 bytes |
| Choice options across envelope | 100 |
| Choice label | 256 UTF-8 bytes |
| Text response per input | 16,384 UTF-8 bytes |
| Block nesting | One `field_group` level |
| IDs | 64 ASCII characters |
| App package compressed size | 10 MiB |
| App package extracted size | 30 MiB |
| App package files | 1,024 |

Text rejects C0/C1 controls other than permitted line breaks and tabs, Unicode
bidirectional override/isolate controls, invalid UTF-8, and leading or trailing
whitespace where the field is an identifier. JSON rejects duplicate keys,
non-integer numbers, noncanonical encoding, and unknown members unless the
owning schema explicitly marks an extension map.

The normative Marmot feature document may lower a package-runtime bound after
platform profiling, but it must use one cross-platform value and update the
conformance fixtures in the same change.

## 17. Error Behavior

| Condition | Required behavior |
| --- | --- |
| Missing or invalid interactive tag | Render kind-`9` fallback normally. |
| Unsupported envelope version | Render fallback and disable structured actions. |
| Unsupported optional block | Render the block fallback and continue. |
| Unsupported required extension | Disable affected actions and explain locally. |
| Invalid response | Retain per normal storage policy but exclude from effective projection. |
| Missing media | Preserve alt text and allow normal attachment retry. |
| Expired prompt | Show read-only content and reject new responses locally. |
| Conflicting `single_accept` responses | Use deterministic projection but do not claim consensus. |
| Invalid app update | Discard that update only. |
| Sandbox failure | Stop the app and show its fallback. |

Error labels shown by clients are localized host strings. Untrusted payload text
must not be presented as a trusted validation or security result.

## 18. MDK API and Projection

MDK owns protocol behavior shared across clients. It adds dedicated APIs rather
than requiring clients to call the generic custom-event method:

- `send_interactive_prompt`
- `respond_to_interaction`
- `send_interactive_app_update`
- interaction lookup and response-history queries

The exact language spelling follows each binding's conventions.

Timeline records expose a nullable validated interaction projection containing:

- interaction identity and revision;
- lifecycle state;
- typed block and action unions;
- supported/unsupported markers and fallbacks;
- current account response;
- effective response summaries allowed by policy;
- verified attachment descriptors; and
- optional interactive-app descriptor and replay cursor.

The FFI uses tagged unions and bounded records. Raw unvalidated JSON is not the
primary client API. Adding this surface requires coordinated updates to Rust,
UniFFI, C, generated bindings, and platform fakes.

## 19. Platform Responsibilities

### 19.1 iOS and macOS

Share Swift projection adapters and SwiftUI block views where platform behavior
matches. Use `WKWebView` with an isolated, nonpersistent data store and a
restricted resource loader for Level 2.

### 19.2 Android

Use Kotlin projection adapters and Jetpack Compose block views. Use a hardened
Android `WebView` with request interception and no ambient JavaScript interfaces
beyond the narrow serialized bridge.

### 19.3 Linux

Use the MDK C projection and native block widgets. Reuse the existing separate
WebKitGTK process for Level 2 and replace only its transport/bridge adapter.

### 19.4 Accessibility

Every native block exposes a semantic label, value, requirement state, error,
and action role. Keyboard traversal follows block order. Image and diagram alt
text is mandatory. Interactive-app fallback remains available when the web
surface is inaccessible.

## 20. Conformance

The `marmot` repository publishes language-neutral fixtures for:

- canonical prompt, response, and state-update event IDs;
- every baseline block and action;
- every response policy;
- revisions, expiry, cancellation, deletion, and invalidation;
- deterministic response selection and tie-breaking;
- duplicate IDs, duplicate JSON keys, invalid UTF-8, and every size boundary;
- unknown optional and required extensions;
- images, Mermaid, passive SVG, and artifact fallbacks;
- attachment and package hash mismatch;
- WebXDC update replay and per-sender sequences; and
- legacy `wnxdc1:` migration examples.

MDK must pass the normative fixture suite. Each platform runs renderer tests
against MDK projections, including accessibility and fallback snapshots. Each
Level 2 host also runs shared malicious-package fixtures for traversal,
decompression limits, navigation, network attempts, script bridge abuse, and
resource exhaustion.

## 21. Delivery Plan

The design is implemented through separate reviewable changes:

1. **Marmot protocol:** Add the normative feature document, kind and tag
   registry entries, schemas, limits, and conformance fixtures.
2. **MDK:** Add validation, persistence, projections, send/respond APIs,
   UniFFI/C surfaces, and protocol-vector tests.
3. **macOS Level 1:** Add native rendering for baseline blocks, graphics,
   fallback, and response submission. Treat `interactive_app` as a validated
   unsupported block with fallback.
4. **iOS, Android, and Linux Level 1:** Implement renderers against the same MDK
   projection.
5. **Level 2:** Add sandboxed hosts and the Linux legacy read adapter.

The first implementation plan should cover steps 1 through 3 while keeping each
repository independently buildable. Level 2 receives a separate plan and
security review.

## 22. Repository and Contribution Strategy

Work uses these forks:

- `liamhelmer/marmot`
- `liamhelmer/mdk`
- `liamhelmer/whitenoise-mac`

Each feature branch starts from the current default branch of its upstream
repository. At design time all three upstreams use `master`. Every commit is
SSH-signed with the contributor's Radicle key. Each repository receives its own
pull request; no pull request is merged automatically.
