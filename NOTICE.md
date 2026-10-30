# Provenance and licensing status

This repository extracts the existing Rex Pluck implementation into a standalone package. It does
not include terminal captures, user screenshots, private configuration, or source repository history.

## Inspiration

The hint-based copying interaction and yellow/cyan palette were inspired by
[Herdr Pluck](https://github.com/rmarganti/herdr-pluck) by rmarganti. Its source was inspected during
development. This Rex implementation uses JavaScript and Lua rather than the upstream Rust plugin;
that difference alone does not establish that all licensing obligations have been resolved.

The upstream `Cargo.toml` at commit `1a6302384098f21835e2964637d39dddc989bc1d` declares `license = "MIT"`:

https://github.com/rmarganti/herdr-pluck/blob/1a6302384098f21835e2964637d39dddc989bc1d/Cargo.toml

That primary source was checked during extraction. No top-level LICENSE file was present in the
inspected upstream checkout, and the corresponding raw LICENSE URL returned 404. The declaration
is recorded as provenance, not a substitute for checking attribution and redistribution obligations.
No upstream binary, Rust source, screenshots, or demos are bundled here.

## This release

A license for this repository has **not** been selected. The package is marked `private` and
`UNLICENSED`; the local `v0.1.0` tag is not a public distribution clearance. Before publishing,
review any adapted material, preserve required notices, and select a license with the owner.
No open-source license grant is made by this repository in its current state.
