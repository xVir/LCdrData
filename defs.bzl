"""Shared build constants for the first-party Swift modules."""

# Mirrors the Tuist build settings in Project.swift. SWIFT_VERSION is 5.0, which
# is why SWIFT_APPROACHABLE_CONCURRENCY expands to five upcoming features here
# rather than the two it would enable in Swift 6 language mode.
SWIFT_COPTS = [
    "-swift-version",
    "5",
    "-default-isolation=MainActor",
    "-enable-upcoming-feature",
    "DisableOutwardActorInference",
    "-enable-upcoming-feature",
    "GlobalActorIsolatedTypesUsability",
    "-enable-upcoming-feature",
    "InferIsolatedConformances",
    "-enable-upcoming-feature",
    "InferSendableFromCaptures",
    "-enable-upcoming-feature",
    "NonisolatedNonsendingByDefault",
    "-enable-upcoming-feature",
    "MemberImportVisibility",
]

# Shared by every first-party module so `package` declarations resolve across
# module boundaries. Must match SWIFT_PACKAGE_NAME in Project.swift.
PACKAGE_NAME = "lcdrdata"
