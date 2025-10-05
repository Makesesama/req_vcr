# Cassette File Management Reference

This document provides a reference for managing cassette files in Reqord, including record modes, file operations, and best practices.

## Record Modes

Reqord supports four record modes that control how cassettes are created, updated, and used during tests.

### `:once`
- **Behavior**: Strict replay mode
- **Use case**: Normal test runs after cassettes are recorded
- **File operations**: Only reads existing cassettes, never modifies files
- **Errors**: Raises `CassetteMissError` if no matching cassette entry found

### `:new_episodes`
- **Behavior**: Replay existing + record new requests
- **Use case**: Adding new test scenarios to existing test suites
- **File operations**: Reads existing cassettes, appends new entries when no match found
- **Safety**: Preserves all existing cassette data

### `:all`
- **Behavior**: Re-record everything
- **Use case**: Refreshing all cassettes with updated API responses
- **File operations**: Replaces entire cassette content with new recordings
- **Warning**: Overwrites existing cassette data completely

### `:none` (Default)
- **Behavior**: Never record, replay only
- **Use case**: Strict testing environments where no network access is allowed
- **File operations**: Only reads existing cassettes, never writes
- **Errors**: Raises error if cassette is missing or incomplete

## Cassette File Operations

### Creation
- Cassettes are created automatically when first request is recorded
- File path: `test/support/cassettes/{ModuleName}/{test_name}.jsonl`
- Directory structure is created automatically if it doesn't exist

### Replacement
- Only occurs in `:all` mode
- Entire cassette file content is replaced with new recordings
- Ensures consistent state by recording all requests in a test session

### User-Only Deletion
**Important**: Cassette files should **never** be deleted by application code.

- Only users should manually delete cassette files when needed
- Code should only create or replace cassettes
- This ensures users are never left without cassettes unexpectedly
- Prevents data loss and maintains test reliability

## Usage Patterns

### Environment Variable Control
```bash
# Default replay mode
mix test

# Append new recordings
REQORD=new_episodes mix test

# Re-record all cassettes
REQORD=all mix test

# Strict replay only
REQORD=none mix test
```

### Per-Test Overrides
```elixir
# Override mode for specific test
@tag vcr_mode: :new_episodes
test "allows new recordings" do
  # This test will record new requests
end

# Custom cassette name
@tag vcr: "custom/cassette_name"
test "with custom cassette location" do
  # Uses custom path instead of auto-generated
end
```

### Integration with Scripts
```bash
# Use the recording script for integration tests
./scripts/record_cassettes.sh

# Record specific test file
./scripts/record_cassettes.sh test/my_test.exs --include integration
```

## Best Practices

### When to Use Each Mode

- **`:none`**: Daily development and CI/CD runs (default)
- **`:once`**: When you have cassettes and want strict replay without network calls
- **`:new_episodes`**: Adding new test cases without losing existing data
- **`:all`**: Refreshing cassettes after API changes or when starting fresh

### Safe Cassette Management

1. **Backup before `:all` mode**: Save existing cassettes before re-recording
2. **Version control**: Always commit cassettes to ensure team consistency
3. **Gradual updates**: Use `:new_episodes` when possible to avoid losing working cassettes
4. **Test isolation**: Ensure each test uses unique cassette names to avoid conflicts

### File Safety Guidelines

- Never implement automatic cassette deletion in code
- Always preserve existing cassettes unless explicitly replacing (`:all` mode)
- Provide clear feedback to users about file operations
- Use atomic operations to prevent partial writes that could corrupt cassettes

## Cassette File Format

Cassettes are stored as JSONL (JSON Lines) files where each line contains one HTTP interaction:

```jsonl
{"req":{"method":"GET","url":"https://api.example.com/users","headers":{},"body_hash":"-"},"resp":{"status":200,"headers":{},"body_b64":"..."}}
{"req":{"method":"POST","url":"https://api.example.com/users","headers":{},"body_hash":"abc123"},"resp":{"status":201,"headers":{},"body_b64":"..."}}
```

This format allows for:
- Sequential replay of requests in chronological order
- Easy inspection and manual editing if needed
- Efficient append operations for `:new_episodes` mode