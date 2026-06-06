# macos-defaults

A macOS-only CLI that captures, diffs, and applies a curated set of scalar macOS
`defaults` (CFPreferences) settings. Drive your Mac through the GUI, then reconcile the
settings you care about into a version-controlled desired-state file and apply it
idempotently across machines.

Scope (v1): scalar preference types only — `bool`, `int`, `float`, `string`. Dictionary,
array, date, and data values are *detected and flagged*, never written.

## Build

    swift build

## Verbs

### `apply <statefile> [--no-reload]`

Read the desired-state file and set each value via CFPreferences. Idempotent. After writing,
best-effort restarts `Dock`, `Finder`, and `SystemUIServer` so changes are picked up — pass
`--no-reload` to skip this. Some settings still require logout/restart.

- Exit `0` on success (including "everything already matched").
- Exit non-zero on a real error (unreadable file, malformed line, write failure).

### `drift <statefile> [--watched <file>] [--noise <file>]`

Report the difference between current effective state and the desired-state:

- `DRIFT  <domain>  <key>  current=<v|unset>  desired=<v>` — a desired key whose live value differs.
- `NEW    <domain>  <key>  current=<v>` — a key set in a *watched* domain that is not in the
  desired-state and not matched by a noise pattern. This is what you triage into the statefile.

Watched domains come from `--watched`, else the domains appearing in the statefile. Noise
filtering applies only to the untracked (`NEW`) enumeration. Keys whose live value is an
unsupported type are reported as `SKIP …` on stderr.

- Exit `0` if clean (nothing to review).
- Exit `1` if there is any `DRIFT` or `NEW` output.
- Exit `2` on error.

### `capture <domain> [<key>...] [--noise <file>]`

Emit desired-state lines (to stdout) for a domain, with types read live from CFPreferences.
With explicit keys, emit just those. With no keys, emit every supported key in the domain,
minus noise (if `--noise` given). Unsupported types and strings containing a TAB or newline are
reported as `SKIP …` on stderr, never emitted. The tool does not edit the statefile itself —
redirect or append the output yourself:

    macos-defaults capture com.apple.finder ShowPathbar >> ~/defaults.tsv

## File formats

### Desired-state file

One entry per line, TAB-separated, four fields:

    <domain>\t<key>\t<type>\t<value>

- `domain` — a CFPreferences application ID (`com.apple.finder`), or the literal `NSGlobalDomain`.
- `key` — the preference key (may contain spaces and dots).
- `type` — one of `bool`, `int`, `float`, `string`.
- `value` — `true`/`false`; a decimal integer; a round-trippable decimal; or literal text.
  String values must not contain a TAB or newline.

Lines are sorted by `(domain, key)` on write. Blank lines and lines beginning with `#` are
ignored. A malformed line is a hard error (exit 2) reporting the line number.

### Watched-domains file (`--watched`)

One domain per line. `#` comments and blank lines ignored.

### Noise file (`--noise`)

One `fnmatch`-style glob per line (`*`, `?`, character classes), matched against the key name.
A key matching any pattern is excluded from `drift`'s `NEW` output and from a whole-domain
`capture`. Examples:

    * Frame
    *Recent*
    NSWindow Frame *

## Testing

    swift test

Unit tests run against an in-memory fake store. The one integration test writes only to the
throwaway domain `com.macos-defaults.itest` and tears it down; no test mutates your real
settings.
