# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/),
and this project adheres to [Semantic Versioning](https://semver.org/).

`JSON.Version`, the `@version` header in `AHK20_JSON.ahk`, and the latest
version heading below must be the same string.

## [Unreleased]

## [1.0.0] - 2026-09-08

### Added

- Strict RFC 8259 parser and serializer for AutoHotkey v2.
- Rejection of trailing NUL after a complete value (`123` + `U+0000`).
- Refusal to treat `U+0000` as JSON whitespace.
- JSONTestSuite `test_parsing` coverage: 318 cases, 0 FAIL.

[Unreleased]: https://github.com/aiascendlab/ahk20-json/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/aiascendlab/ahk20-json/releases/tag/v1.0.0
