# License and provenance

This repository extracts the existing Rex Pluck implementation into a standalone package. It does
not include terminal captures, user screenshots, private configuration, or source repository history.

## Inspiration

The hint-based copying interaction and yellow/cyan palette were inspired by
[Herdr Pluck](https://github.com/rmarganti/herdr-pluck) by rmarganti. Its source was inspected during
development. This Rex implementation uses embedded Lua rather than the upstream Rust plugin;
that difference alone does not establish that all licensing obligations have been resolved.

The upstream `Cargo.toml` at commit `1a6302384098f21835e2964637d39dddc989bc1d` declares `license = "MIT"`:

https://github.com/rmarganti/herdr-pluck/blob/1a6302384098f21835e2964637d39dddc989bc1d/Cargo.toml

That primary source was checked during extraction. No top-level LICENSE file was present in the
inspected upstream checkout, and the corresponding raw LICENSE URL returned 404. The declaration
is recorded as provenance, not a substitute for checking attribution and redistribution obligations.
No upstream binary, Rust source, screenshots, or demos are bundled here.

## Unicode data

`pluck/unicode.lua` and `tests/data/GraphemeBreakTest.txt` derive from the Unicode 17.0.0 UCD:
https://www.unicode.org/Public/17.0.0/ucd/

The property sources are UnicodeData.txt, DerivedCoreProperties.txt, auxiliary/GraphemeBreakProperty.txt,
and emoji/emoji-data.txt. The grapheme vectors come from auxiliary/GraphemeBreakTest.txt.
Their Unicode License v3 copyright and permission notice is retained in [LICENSE.unicode](LICENSE.unicode).
`scripts/update-unicode.py` regenerates the vendored data; it is not called during installation,
normal tests, or runtime. This data license is separate from the MIT license for this repository's code.

## This release

This repository is licensed under the MIT License. See [LICENSE](LICENSE) for the copyright notice,
permissions, and warranty disclaimer. Upstream authors retain their rights and notice requirements
in any material adapted from their work; the attribution above is retained.

The npm package remains marked `private` to prevent accidental npm publication; this does not restrict
the permissions granted by the MIT License.
