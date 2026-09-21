# MarmotKit 0.10.4 migration boundary

White Noise for macOS now pins `marmotkit-v0.10.4` at MDK commit
`fcc85edd8dbd07c8293c899ee52230f72c54c897`.

This release upgrades account databases through MDK migrations 57–89. Opening an account with
this build is a one-way compatibility boundary: an older White Noise build using MarmotKit 0.9.x
must not reopen that upgraded database. Preserve a pre-upgrade copy when rollback evidence is
required; rolling back the application binary is not a database rollback.

The macOS package is the published arm64 static-library distribution. Its generated Swift source,
binary artifact, release manifest, and separately checksummed `PrivacyInfo.xcprivacy` are installed
as one verified release by `just sync-bindings`. `just sanity` verifies the release tag, source SHA,
binary checksum, generated-source hash, privacy checksum, declared distribution, Swift package
resource, and bundled privacy manifest before delivery.

`whitenoise-macTests/Fixtures/MarmotKit-0.9.16-account-root.zip` is an immutable account-root
fixture created by the published 0.9.16 binary (`908780b383046ac56b84b9e74b2e8c33389c1e9b`).
Its SHA-256 is `fbe5e3e903a6b1c08393bfbe0f77d0dd4495815e2f16fe9b084312dc219a6e99`.
The fixture intentionally retains its SQLite WAL files: the migration suite verifies both the
first 0.10.4 open and a second open after migration, and separately proves recovery from the
WAL-backed state left by the old runtime. It contains no signing key; account secrets remain in
Keychain and are not part of the archive.

Attachment acquisition is host managed. Until the account is locally ready and the stored user
policy has loaded, every automatic attachment category is denied. A user-initiated download remains
available independently of that automatic permission.
