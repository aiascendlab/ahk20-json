# Contributing

Maintained by **AI Ascend Lab**. Bug reports and focused pull requests are welcome.

## Development setup

1. Install [AutoHotkey v2](https://www.autohotkey.com/).
2. Clone this repository.
3. From the repo root, run the same check CI uses:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\test\check.ps1
```

If you have `make`:

```text
make check
```

JSONTestSuite (318 isolated processes) is **not** part of the default check:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\test\check.ps1 -Suite
```

or `make test-suite`.

## Running checks

| Command | What it runs |
|---|---|
| `test/check.ps1` / `make check` | `test/JSON_full_test.ahk` and `examples/basic.ahk` |
| `test/check.ps1 -Suite` / `make test-suite` | nst/JSONTestSuite parsing samples |

Keep 0 FAIL on JSONTestSuite if you change the parser.

## Branching and commits

- Branch from `main`: `feat/…`, `fix/…`, `docs/…`
- [Conventional Commits](https://www.conventionalcommits.org/): `feat:`, `fix:`, `docs:`, `chore:`, …
- One pull request, one problem
- Sign off every commit (`git commit -s`) for the [Developer Certificate of Origin](https://developercertificate.org/)

## Pull requests

- Title is the squash commit message (Conventional Commits)
- Link issues with `Closes #123`
- Add or update tests and docs; breaking changes must say **BREAKING**
- Declare AI involvement (see below)

## Developer Certificate of Origin (DCO)

All commits must include a `Signed-off-by:` line (`git commit -s`), stating you have the right to submit the code.

## Use of AI tools

AI-assisted coding is allowed, but:

- You must understand and be able to explain every line you submit
- The PR description must say how AI was used (for example “drafted with an AI coding agent, then reviewed and tested by me”)
- Unverified AI-generated vulnerability reports will be closed
- Maintainers may reject bulk PRs that were clearly not reviewed by a human

## Reporting bugs / requesting features

Use the GitHub Issue forms. Usage questions belong in [Discussions](https://github.com/aiascendlab/ahk20-json/discussions). Security issues go to [SECURITY.md](SECURITY.md), not public issues.

## Tooling notes

Some items from the team repository standard are intentionally not applied here:

- **No CodeQL**: it does not support AutoHotkey or PowerShell.
- **No package publishing workflow**: the deliverable is the single file `AHK20_JSON.ahk`, attached to each GitHub Release by hand.
- **No formatter or linter step**: AutoHotkey has no standard one. `#Warn All, StdOut` in the test scripts is the closest equivalent.
- **No CODEOWNERS or architecture docs**: single maintainer, single file. Design constraints live in the header of `AHK20_JSON.ahk` and in [docs/api.md](docs/api.md).
