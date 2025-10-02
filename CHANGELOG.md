# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- **Pluggable JSON system** - Support for custom JSON libraries via `ReqVCR.JSON` behavior
  - `ReqVCR.JSON.Jason` adapter (default) with runtime availability checks
  - `ReqVCR.JSON.Poison` adapter with graceful fallback when not available
  - Application config: `config :req_vcr, :json_library, MyAdapter`
  - Comprehensive adapter test suite with real cassette creation/loading
- **CassetteEntry struct** - Type-safe cassette data modeling with validation
  - Nested `ReqVCR.CassetteEntry.Request` and `Response` structs
  - Built-in validation with helpful error messages
  - Helper functions: `new/2`, `from_raw/1`, `to_map/1`, `validate/1`
- **Test utilities** - Shared helpers to reduce test code duplication
  - `ReqVCR.TestHelpers.with_module/3` for conditional module tests
  - `ReqVCR.TestHelpers.with_config/4` for application config setup/teardown
  - `ReqVCR.TestHelpers.with_module_and_config/6` combining both patterns
- **Development tools** - Mix task for code quality enforcement
  - `mix precommit` alias running format, credo, dialyzer, and tests
- **Configurable settings** - Made hard-coded values configurable for flexibility
  - `ReqVCR.Config` module for centralized configuration management
  - Configurable cassette directory: `config :req_vcr, :cassette_dir, "custom/path"`
  - Configurable auth parameters: `config :req_vcr, :auth_params, ~w[token my_token]`
  - Configurable auth headers: `config :req_vcr, :auth_headers, ~w[authorization x-my-auth]`
  - Configurable volatile headers: `config :req_vcr, :volatile_headers, ~w[date x-trace-id]`
  - Configuration validation with helpful error messages
  - Comprehensive test coverage for all configuration options

### Changed
- **Improved error handling** throughout the codebase
  - Replaced bare `rescue _ -> body` clauses with specific exception handling
  - Added logging for JSON decoding failures and network errors during recording
  - Consistent use of `case` statements instead of exception-prone `!` functions
- **Better test organization** - Separated JSONL format tests into dedicated file
  - `test/req_vcr/jsonl_test.exs` for JSONL-specific functionality
  - `test/req_vcr/json/` directory for JSON adapter tests
  - Improved test cleanup preserving fixture files
- **Optional dependencies** - Made JSON libraries optional to reduce bloat
  - Jason and Poison marked as `optional: true` in mix.exs
  - Runtime checks with helpful error messages when libraries are missing

### Fixed
- **Error handling security** - Prevented silent failures that could mask issues
- **Test reliability** - Fixed cassette cleanup logic to preserve fixture directories
- **Code quality** - Resolved Credo warnings for negated conditions and formatting
- **Hard-coded values** - Eliminated hard-coded cassette directory, auth parameters, and volatile headers
  - All previously hard-coded values are now configurable via application config
  - Maintains backward compatibility with sensible defaults

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
