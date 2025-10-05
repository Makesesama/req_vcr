# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- **Object and Streaming Support** - Comprehensive support for binary data and streaming responses
  - **Smart Content Detection** - Automatic detection of binary vs text content based on Content-Type headers and heuristics
  - **External Object Storage** - Large binary objects stored externally to prevent JSONL bloat
  - **Streaming Response Support** - Capture and replay of streaming responses (SSE, chunked transfer)
  - **Configurable Storage Thresholds** - Control when to use external vs inline storage
  - **Enhanced CassetteEntry.Response** - New fields for body_encoding, body_external_ref, and stream_metadata
  - **Pluggable Storage Extensions** - Extended Storage.Behavior with object and stream storage methods

### Changed
- **Enhanced Response Creation** - New `CassetteEntry.Response.new_with_raw_body/3` for automatic encoding detection
- **Improved Replay System** - Enhanced body loading with support for external storage and streaming content
- **Extended Configuration** - New config options for max_inline_size, object_directory, binary_storage, and stream_speed

## [0.3.0] - 2025-10-05

### Added
- **NEW ARCHITECTURE: Timestamp-based chronological ordering** - Complete redesign to solve request ordering issues
  - **Microsecond precision timestamps** - All cassette entries now include `recorded_at` field with microsecond timestamps
  - **Async CassetteWriter GenServer** - Non-blocking writes with batching and automatic timestamp sorting
  - **Streaming CassetteReader** - Memory-efficient reading with chronological ordering by timestamp
  - **Pluggable Storage Backend** - New `Reqord.Storage.Behavior` interface for future S3/Redis support
  - **FileSystem Storage Backend** - Optimized JSONL file operations with atomic writes and streaming reads
  - **Application Supervision** - CassetteWriter automatically starts with Reqord application
  - **Enhanced Test Flushing** - Automatic cassette flushing on test completion via `Reqord.cleanup/1`
- **Pure Sequential Streaming** - Revolutionary performance improvement for cassette replay
  - **No search operations** - Direct O(1) access instead of O(n) searching through entries
  - **Sequential verification** - Takes next entry and verifies match instead of searching for matches
  - **Optimized common case** - Fast path for default `[:method, :uri]` matching used in 90%+ of cases

### Fixed
- **CRITICAL: POST-DELETE lifecycle ordering** - Solved concurrent request recording order issues
  - **Problem**: Concurrent requests (e.g., parallel POST-DELETE lifecycles) were recorded in completion order, not initiation order
  - **Solution**: Timestamp-based recording ensures chronological replay even when requests complete out of order
  - **Impact**: Eliminates ID mismatch errors in cassette replay for concurrent scenarios
  - **Example**: POST (user creation) → DELETE (user deletion) lifecycles now maintain correct order during replay
- **CRITICAL: Concurrent request recording in :all mode** - Fixed issue where HTTP requests made from spawned processes weren't being recorded
  - Problem: Reqord used process dictionary to accumulate requests in `:all` mode, but spawned processes (Task.async, etc.) don't inherit parent's process dictionary
  - Solution: Replaced process dictionary with GenServer-based state management following ExVCR's proven architecture pattern
  - Impact: Concurrent HTTP requests from Task.async and other spawned processes are now properly recorded in `:all` mode
  - Scope: Only affects `:all` mode - other modes (`:once`, `:new_episodes`, `:none`) unchanged and working correctly

### Changed
- **BREAKING: Cassette format change** - All cassettes now require timestamps
  - **Migration Required**: Existing cassettes without timestamps will not load
  - **Solution**: Regenerate all cassettes using `REQORD=all mix test`
  - **Benefit**: Enables chronological replay ordering and future extensibility
- **BREAKING: Removed legacy timestamp compatibility** - Clean implementation without backward compatibility
  - No automatic timestamp addition for legacy entries
  - Simplified codebase with consistent timestamp requirements
  - Better error messages for invalid cassette entries
- **BREAKING: Sequential replay is now the only strategy** - Removed complex dual matching approaches
  - **Eliminated**: Search-based "last match wins" strategy that was slower and more error-prone
  - **Unified**: Single sequential streaming approach for all scenarios
  - **Improved**: Better error messages with `SequenceMismatchError` showing exact position and expected vs actual requests
  - **Simplified**: Much cleaner codebase with reduced cognitive overhead

### Removed
- **Legacy cassette support** - No longer supports cassettes without timestamps for cleaner architecture
- **Search-based matching** - Removed complex search algorithms in favor of simple sequential access
- **Duplicate code** - Eliminated duplicate `put_headers` functions across modules

### Performance
- **MAJOR: O(1) cassette replay** - Eliminated O(n) search operations for massive performance improvement on large cassettes
- **Async writes** - Non-blocking cassette writes during test execution
- **Streaming operations** - Memory-efficient reading for large cassette files
- **Batched I/O** - Reduced file system operations through intelligent batching
- **Timestamp sorting** - Automatic chronological ordering without manual intervention
- **Optimized matching** - Inlined fast path for most common matching scenarios

## [0.2.2] - 2025-10-03

### Fixed
- **CRITICAL: Multiple requests in :all mode** - Fixed `:all` mode to properly handle multiple requests
  - In `:all` mode, each request now accumulates and replaces the entire test cassette with all requests
  - This ensures all requests in a test are recorded while never clearing cassettes from other tests
  - Each test gets a fresh cassette containing only its requests when using `REQORD=all`
  - Fixes the issue where running `REQORD=all mix test specific_test.exs` would inappropriately clear cassettes

## [0.2.1] - 2025-10-03

### Fixed
- **CRITICAL: Record mode behavior** - Fixed `:all` mode to follow Ruby VCR behavior
  - `:all` mode now always replaces the entire cassette (instead of appending)
  - This fixes the critical issue where rerecording would mix old broken requests with new fixed ones
  - Simplified implementation by removing complex session tracking in favor of Ruby VCR's straightforward approach
  - `:all` mode now never replays - always goes live and records fresh responses
  - Ensures that `REQORD=all` provides clean, predictable cassette replacement behavior
- **Code quality** - Fixed all test warnings and Credo issues
  - Resolved unused variable warnings in test files
  - Fixed alias ordering and unused alias warnings
  - Refactored complex functions to reduce cyclomatic complexity
  - Improved code readability and maintainability

### Added
- **Comprehensive test coverage** - Extensive edge case testing across all modules
  - Redactor tests for extreme token lengths (1-10000 characters) and boundary cases
  - URL normalization edge cases including malformed URLs and unicode handling
  - Base64 encoding/decoding stress tests with large data and concurrent operations
  - Cassette file format edge cases (mixed line endings, BOM markers, malformed JSON)
  - HTTP request/response validation for unusual methods and status codes
  - Record mode integration tests simulating real-world broken→fixed workflows
  - Last-match-wins replay strategy tests for handling mixed cassette scenarios
  - Large file handling and concurrent access patterns
  - Memory and performance considerations for encoding operations
- **Documentation improvements** - Added hex package badges to README

### Changed
- **Simplified architecture** - Removed Session module complexity
  - Eliminated Agent-based session tracking that was causing confusion
  - Record logic now follows simple Ruby VCR patterns without stateful tracking
  - Cleaner, more predictable behavior that matches developer expectations
  - Reduced cognitive overhead for understanding and debugging record modes

## [0.2.0] - 2025-10-02

### Added
- **Pluggable JSON system** - Support for custom JSON libraries via `Reqord.JSON` behavior
  - `Reqord.JSON.Jason` adapter (default) with runtime availability checks
  - `Reqord.JSON.Poison` adapter with graceful fallback when not available
  - Application config: `config :reqord, :json_library, MyAdapter`
  - Comprehensive adapter test suite with real cassette creation/loading
- **CassetteEntry struct** - Type-safe cassette data modeling with validation
  - Nested `Reqord.CassetteEntry.Request` and `Response` structs
  - Built-in validation with helpful error messages
  - Helper functions: `new/2`, `from_raw/1`, `to_map/1`, `validate/1`
- **Test utilities** - Shared helpers to reduce test code duplication
  - `Reqord.TestHelpers.with_module/3` for conditional module tests
  - `Reqord.TestHelpers.with_config/4` for application config setup/teardown
  - `Reqord.TestHelpers.with_module_and_config/6` combining both patterns
- **Development tools** - Mix task for code quality enforcement
  - `mix precommit` alias running format, credo, dialyzer, and tests
- **Configurable settings** - Made hard-coded values configurable for flexibility
  - `Reqord.Config` module for centralized configuration management
  - Configurable cassette directory: `config :reqord, :cassette_dir, "custom/path"`
  - Configurable auth parameters: `config :reqord, :auth_params, ~w[token my_token]`
  - Configurable auth headers: `config :reqord, :auth_headers, ~w[authorization x-my-auth]`
  - Configurable volatile headers: `config :reqord, :volatile_headers, ~w[date x-trace-id]`
  - Configuration validation with helpful error messages
  - Comprehensive test coverage for all configuration options

### Changed
- **Improved error handling** throughout the codebase
  - Replaced bare `rescue _ -> body` clauses with specific exception handling
  - Added logging for JSON decoding failures and network errors during recording
  - Consistent use of `case` statements instead of exception-prone `!` functions
- **Better test organization** - Separated JSONL format tests into dedicated file
  - `test/reqord/jsonl_test.exs` for JSONL-specific functionality
  - `test/reqord/json/` directory for JSON adapter tests
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
- Initial release of Reqord
- Core `Reqord` module with `install!/1` for setting up VCR stubs
- Ruby VCR-style record modes: `:once`, `:new_episodes`, `:all`, `:none`
  - `:once` - Strict replay, raise on new requests (default)
  - `:new_episodes` - Replay existing, record new requests (append mode)
  - `:all` - Always re-record everything, ignore existing cassette
  - `:none` - Never record, never hit network (must have complete cassette)
- `Reqord.Case` ExUnit case template for automatic cassette management
- Smart request matching based on method, normalized URL, and body hash
- Automatic redaction of sensitive headers (`authorization`)
- Automatic redaction of auth query parameters (`token`, `apikey`, `api_key`)
- Automatic removal of volatile response headers (`date`, `server`, `set-cookie`, etc.)
- JSONL cassette format stored in `test/support/cassettes/`
- Query parameter normalization (lexicographic sorting, auth param removal)
- Body hash differentiation for POST/PUT/PATCH requests
- Support for spawned processes via `allow/3` helper
- Multiple configuration options for record mode:
  - Environment variable via `REQORD`
  - Application config via `:reqord, :default_mode`
  - Per-test override via `@tag vcr_mode: :mode`
- Automatic cassette naming based on test module and test name
- Custom cassette naming via `@tag vcr: "custom_name"`
- Custom stub name override via `@tag req_stub_name: MyStub`
- Integration with `Req.Test` for zero application code changes
- Comprehensive test suite covering all modes and features
- Detailed README with setup, usage examples, and troubleshooting
- Mix tasks for cassette management:
  - `mix reqord.show` - Display cassette contents with filtering options
  - `mix reqord.audit` - Audit cassettes for secrets, staleness, and unused entries
  - `mix reqord.prune` - Clean up empty files, duplicates, and stale cassettes
  - `mix reqord.rename` - Rename or move cassettes, with migration support
- Flexible request matching system:
  - Built-in matchers: `:method`, `:uri`, `:host`, `:path`, `:headers`, `:body`
  - Custom matcher registration via `register_matcher/2`
  - Default matching on `[:method, :uri]`
  - Per-test matcher override via `@tag match_on: [...matchers]`
  - Application config for default matchers
- Test API application (`test_api/`) for demonstrating Reqord:
  - Simple REST API with authentication
  - Multiple routes (GET /api/users, GET /api/users/:id, POST /api/users)
  - Fake Bearer token authentication
  - Example tests showing real-world usage
- Automated cassette recording script (`scripts/record_cassettes.sh`):
  - Automatically starts test API server
  - Records all example cassettes
  - Stops server when complete
- Comprehensive secret redaction system (`Reqord.Redactor`):
  - **CRITICAL SECURITY**: Ensures secrets never get committed to git cassettes
  - Built-in redaction for auth headers, query parameters, response bodies
  - VCR-style configurable filters for app-specific secrets
  - Multi-layer protection: headers → query params → JSON keys → pattern matching
  - Automatic redaction of Bearer tokens, API keys, long alphanumeric strings
  - Support for GitHub tokens, Stripe keys, UUIDs, and custom patterns

[Unreleased]: https://github.com/Makesesama/reqord/compare/v0.3.0...HEAD
[0.3.0]: https://github.com/Makesesama/reqord/compare/v0.2.2...v0.3.0
[0.2.2]: https://github.com/Makesesama/reqord/compare/v0.2.1...v0.2.2
[0.2.1]: https://github.com/Makesesama/reqord/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/Makesesama/reqord/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/Makesesama/reqord/releases/tag/v0.1.0
