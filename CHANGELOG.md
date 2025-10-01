# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2025-10-02

### Added
- Initial release of ReqVCR
- Core `ReqVCR` module with `install!/1` for setting up VCR stubs
- Ruby VCR-style record modes: `:once`, `:new_episodes`, `:all`, `:none`
  - `:once` - Strict replay, raise on new requests (default)
  - `:new_episodes` - Replay existing, record new requests (append mode)
  - `:all` - Always re-record everything, ignore existing cassette
  - `:none` - Never record, never hit network (must have complete cassette)
- `ReqVCR.Case` ExUnit case template for automatic cassette management
- Smart request matching based on method, normalized URL, and body hash
- Automatic redaction of sensitive headers (`authorization`)
- Automatic redaction of auth query parameters (`token`, `apikey`, `api_key`)
- Automatic removal of volatile response headers (`date`, `server`, `set-cookie`, etc.)
- JSONL cassette format stored in `test/support/cassettes/`
- Query parameter normalization (lexicographic sorting, auth param removal)
- Body hash differentiation for POST/PUT/PATCH requests
- Support for spawned processes via `allow/3` helper
- Multiple configuration options for record mode:
  - Environment variable via `REQ_VCR`
  - Application config via `:req_vcr, :default_mode`
  - Per-test override via `@tag vcr_mode: :mode`
- Automatic cassette naming based on test module and test name
- Custom cassette naming via `@tag vcr: "custom_name"`
- Custom stub name override via `@tag req_stub_name: MyStub`
- Integration with `Req.Test` for zero application code changes
- Comprehensive test suite covering all modes and features
- Detailed README with setup, usage examples, and troubleshooting
- Mix tasks for cassette management:
  - `mix req_vcr.show` - Display cassette contents with filtering options
  - `mix req_vcr.audit` - Audit cassettes for secrets, staleness, and unused entries
  - `mix req_vcr.prune` - Clean up empty files, duplicates, and stale cassettes
  - `mix req_vcr.rename` - Rename or move cassettes, with migration support
- Flexible request matching system:
  - Built-in matchers: `:method`, `:uri`, `:host`, `:path`, `:headers`, `:body`
  - Custom matcher registration via `register_matcher/2`
  - Default matching on `[:method, :uri]`
  - Per-test matcher override via `@tag match_on: [...matchers]`
  - Application config for default matchers
- Test API application (`test_api/`) for demonstrating ReqVCR:
  - Simple REST API with authentication
  - Multiple routes (GET /api/users, GET /api/users/:id, POST /api/users)
  - Fake Bearer token authentication
  - Example tests showing real-world usage
- Automated cassette recording script (`scripts/record_cassettes.sh`):
  - Automatically starts test API server
  - Records all example cassettes
  - Stops server when complete
- Comprehensive secret redaction system (`ReqVCR.Redactor`):
  - **CRITICAL SECURITY**: Ensures secrets never get committed to git cassettes
  - Built-in redaction for auth headers, query parameters, response bodies
  - VCR-style configurable filters for app-specific secrets
  - Multi-layer protection: headers → query params → JSON keys → pattern matching
  - Automatic redaction of Bearer tokens, API keys, long alphanumeric strings
  - Support for GitHub tokens, Stripe keys, UUIDs, and custom patterns

[Unreleased]: https://github.com/Makesesama/req_vcr/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/Makesesama/req_vcr/releases/tag/v0.1.0
