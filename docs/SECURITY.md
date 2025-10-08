# Security & Redacting Secrets

When recording HTTP interactions, it's critical to prevent sensitive data like API keys, tokens, and passwords from being stored in cassettes. Reqord provides automatic and manual redaction strategies.

## Automatic Redaction

Reqord automatically redacts common auth parameters **by default**:

### Redacted by Default

- **Query parameters**: `token`, `apikey`, `api_key`, `key`, `secret`, `password`
- **Headers**: `Authorization`, `X-API-Key`, `X-Auth-Token`, `Cookie`, `Set-Cookie`

These are replaced with `[REDACTED]` in cassettes automatically.

### Example

```elixir
# Request with API key
Req.get("https://api.example.com/users?apikey=secret123")

# Cassette stores:
# url: "https://api.example.com/users?apikey=[REDACTED]"
```

## Custom Redaction

### Redact Query Parameters

Add custom query parameters to redact:

```elixir
# config/test.exs
config :reqord,
  redact_query_params: [:token, :apikey, :session_id, :user_token]
```

### Redact Headers

Add custom headers to redact:

```elixir
# config/test.exs
config :reqord,
  redact_headers: ["authorization", "x-api-key", "x-custom-token"]
```

**Note**: Header names are case-insensitive.

### Redact Request Bodies

For request bodies containing sensitive data, use custom matchers to avoid storing them:

```elixir
# Don't match on body if it contains secrets
@tag match_on: [:method, :path]
test "login request" do
  Req.post(url, json: %{
    username: "user",
    password: "secret"  # Not stored when body matching disabled
  })
end
```

Or sanitize bodies before recording:

```elixir
# In your test helper
def sanitize_body(body) do
  body
  |> Map.put("password", "[REDACTED]")
  |> Map.put("api_key", "[REDACTED]")
end
```

## Response Redaction

### Redact Response Headers

Response headers are also automatically redacted:

```elixir
config :reqord,
  redact_response_headers: ["set-cookie", "x-session-token"]
```

### Redact Response Bodies

For sensitive data in response bodies (like emails, account IDs, or PII), use the `mix reqord.edit` task:

```bash
# Record cassette normally
REQORD=new_episodes mix test test/my_app/account_test.exs

# Edit the cassette to redact sensitive data
mix reqord.edit AccountTest/fetches_user.jsonl
```

In your editor, modify the response body:

```json
{
  "req": { ... },
  "resp": {
    "status": 200,
    "body": "{\"name\":\"John Doe\",\"email\":\"[REDACTED]\",\"ssn\":\"[REDACTED]\"}"
  }
}
```

The task handles JSONL parsing and validation automatically.

**Workflow:**
1. Record cassette with real data (`REQORD=new_episodes mix test`)
2. Edit cassette to redact sensitive fields (`mix reqord.edit cassette.jsonl`)
3. Verify cassette still works (`mix test`)
4. Commit redacted cassette to git

**Edit specific entries:**

```bash
# Edit only the first entry (0-based index)
mix reqord.edit cassette.jsonl --entry 0

# Edit entries matching a URL pattern
mix reqord.edit cassette.jsonl --grep "/users"
```

## Automatic Programmatic Redaction

For advanced redaction scenarios, use the `redact_cassette` macro to define custom redaction functions that run automatically during recording and replay:

### Basic Usage

```elixir
defmodule MyApp.APITest do
  use Reqord.Case
  import Reqord.RedactCassette

  test "user data with automatic redaction" do
    redact_cassette redactor: &user_redactor/1 do
      client = Req.new(plug: {Req.Test, MyApp.ReqStub})
      {:ok, resp} = Req.get(client, url: "/api/users/123")

      # Test sees redacted data for consistency
      assert resp.body["email"] == "[EMAIL_REDACTED]"
      assert resp.body["name"] == "John Doe"  # not redacted
    end
  end

  # Define custom redaction function
  defp user_redactor(_context) do
    %{
      response_body_json: fn json_data ->
        json_data
        |> Map.put("email", "[EMAIL_REDACTED]")
        |> Map.put("ssn", "[SSN_REDACTED]")
      end,
      request_headers: fn headers ->
        Map.put(headers, "x-api-key", "[API_KEY_REDACTED]")
      end
    }
  end
end
```

### Redaction Function Types

The `redact_cassette` macro supports different types of redaction:

```elixir
%{
  # JSON response bodies (automatic encoding/decoding)
  response_body_json: fn json_data ->
    Map.put(json_data, "secret", "[REDACTED]")
  end,

  # Raw binary response bodies (full control)
  response_body_raw: fn body ->
    String.replace(body, "sensitive_pattern", "[REDACTED]")
  end,

  # Request headers
  request_headers: fn headers ->
    Map.put(headers, "authorization", "[AUTH_REDACTED]")
  end,

  # Response headers
  response_headers: fn headers ->
    Map.put(headers, "set-cookie", "[COOKIE_REDACTED]")
  end,

  # URLs (including query parameters)
  url: fn url ->
    URI.parse(url)
    |> Map.update(:query, nil, fn query ->
      if query do
        query
        |> URI.decode_query()
        |> Map.put("token", "[TOKEN_REDACTED]")
        |> URI.encode_query()
      else
        nil
      end
    end)
    |> URI.to_string()
  end
}
```

### Named Redactors

Define reusable redactors in your application config:

```elixir
# config/test.exs
config :reqord,
  redactors: %{
    user_api: fn _context ->
      %{
        response_body_json: &MyApp.Redactors.redact_user_data/1,
        request_headers: &MyApp.Redactors.redact_auth_headers/1
      }
    end,
    financial_api: fn _context ->
      %{
        response_body_json: fn json_data ->
          json_data
          |> Map.put("account_number", "[ACCOUNT_REDACTED]")
          |> Map.put("ssn", "[SSN_REDACTED]")
        end
      }
    end
  }
```

Then use them in tests:

```elixir
test "user API call" do
  redact_cassette redactor: :user_api do
    # test code
  end
end
```

### Complex Nested Redaction

Handle deeply nested data structures:

```elixir
defp nested_redactor(_context) do
  %{
    response_body_json: &redact_nested_secrets/1
  }
end

defp redact_nested_secrets(data) when is_map(data) do
  Enum.reduce(data, %{}, fn {key, value}, acc ->
    cond do
      key in ["email", "api_key", "secret", "token", "password"] ->
        Map.put(acc, key, "[#{String.upcase(key)}_REDACTED]")

      is_map(value) ->
        Map.put(acc, key, redact_nested_secrets(value))

      is_list(value) ->
        Map.put(acc, key, Enum.map(value, &redact_nested_secrets/1))

      true ->
        Map.put(acc, key, value)
    end
  end)
end

defp redact_nested_secrets(data), do: data
```

### Inline Redaction Functions

For simple cases, define redaction inline:

```elixir
test "simple redaction" do
  redact_cassette redactor: fn _context ->
    %{
      response_body_json: fn json_data ->
        Map.put(json_data, "email", "[REDACTED]")
      end
    }
  end do
    # test code
  end
end
```

### Key Benefits

- **Automatic Application**: Redaction runs during both recording and replay
- **JSON-Aware**: Automatic JSON detection and encoding/decoding
- **Configurable JSON Backend**: Uses your configured `Reqord.JSON` library
- **Consistent Testing**: Tests see redacted data for predictable assertions
- **No Manual Editing**: No need to manually edit cassettes after recording
- **Reusable**: Named redactors can be shared across multiple tests

## Best Practices

### 1. Prefer Automatic Redaction

Use the `redact_cassette` macro for consistent, automated redaction:

```elixir
# ✅ Good - Automatic redaction
test "api call" do
  redact_cassette redactor: :user_api do
    # API call - redaction applied automatically
  end
end

# ❌ Less ideal - Manual editing required
test "api call" do
  # API call - requires manual cassette editing afterward
end
```

### 2. Use Named Redactors for Consistency

Define reusable redactors in config to ensure consistency across your test suite:

```elixir
# config/test.exs
config :reqord,
  redactors: %{
    user_api: fn _context -> %{response_body_json: &redact_user_data/1} end,
    payment_api: fn _context -> %{response_body_json: &redact_payment_data/1} end
  }
```

### 3. Review Cassettes Before Committing

Always review new cassettes before committing:

```bash
# After recording new cassettes
git diff test/support/cassettes/

# Check for sensitive data (even with automatic redaction)
grep -r "secret\|password\|token" test/support/cassettes/
```

### 4. Use Environment Variables

Never hardcode secrets in tests:

```elixir
# ❌ Bad
test "api call" do
  Req.get(url, auth: {:bearer, "sk-1234567890abcdef"})
end

# ✅ Good
test "api call" do
  api_key = System.get_env("TEST_API_KEY") || "[REDACTED]"
  Req.get(url, auth: {:bearer, api_key})
end
```

### 5. Add Cassettes to .gitignore (When Necessary)

For highly sensitive projects, consider not committing cassettes:

```gitignore
# .gitignore
test/support/cassettes/
!test/support/cassettes/.gitkeep
```

Then record cassettes locally during development.

### 6. Use Different Keys for Tests

Use separate API keys for testing that have limited permissions:

```elixir
# config/test.exs
config :my_app,
  api_key: System.get_env("TEST_API_KEY") || "test-key-with-limited-access"
```

### 7. Sanitize Object Storage

If using external object storage for binaries, ensure sensitive files are redacted:

```elixir
config :reqord,
  binary_storage: :inline  # Store inline for sensitive data (with caution)
```

Or exclude object directories:

```gitignore
# .gitignore
test/support/cassettes/objects/
```

## URL Normalization

Reqord automatically normalizes URLs to prevent auth data leakage:

```elixir
# URLs with auth are normalized
"https://user:pass@api.example.com/data"
# Becomes:
"https://api.example.com/data"
# Auth stored separately and redacted
```

## Checking for Leaks

### Before Committing

```bash
# Search for common secret patterns
grep -rE "(sk-|api[_-]?key|password|secret)" test/support/cassettes/

# Check for base64-encoded secrets (common in auth headers)
grep -rE "[A-Za-z0-9+/]{40,}={0,2}" test/support/cassettes/
```

### Pre-commit Hook

Add a pre-commit hook to catch secrets:

```bash
#!/bin/bash
# .git/hooks/pre-commit

if git diff --cached --name-only | grep -q "cassettes.*\.jsonl$"; then
  if git diff --cached | grep -iE "password|secret|api[_-]?key" | grep -v "\[REDACTED\]"; then
    echo "⚠️  WARNING: Possible secret in cassette files!"
    echo "Please review your cassettes before committing."
    exit 1
  fi
fi
```

## What Gets Redacted

### ✅ Automatically Redacted

- Common auth query params (`token`, `apikey`, etc.)
- Authorization headers
- Cookie headers
- URL auth (`user:pass@`)

### ⚠️ May Require Custom Redaction

- Application-specific sensitive fields in response bodies
- Custom auth query params not covered by defaults
- Binary files with embedded secrets
- Complex nested data structures with sensitive information

## Example Configuration

Complete security-focused configuration:

```elixir
# config/test.exs
config :reqord,
  # Recording mode
  default_mode: :none,

  # Redaction
  redact_query_params: [
    :token,
    :apikey,
    :api_key,
    :key,
    :secret,
    :password,
    :session_id,
    :auth_token,
    :access_token
  ],

  redact_headers: [
    "authorization",
    "x-api-key",
    "x-auth-token",
    "x-session-token",
    "cookie",
    "set-cookie"
  ],

  redact_response_headers: [
    "set-cookie",
    "x-session-token",
    "x-csrf-token"
  ],

  # Storage
  binary_storage: :external,  # Keep cassettes readable
  max_inline_size: 10_240     # 10KB limit for inline storage
```

## Emergency: Secret Leaked

If you accidentally commit a secret:

### 1. Rotate the Secret Immediately

Change the compromised API key/token/password.

### 2. Remove from Git History

```bash
# Remove file from history
git filter-branch --force --index-filter \
  "git rm --cached --ignore-unmatch test/support/cassettes/leaked.jsonl" \
  --prune-empty --tag-name-filter cat -- --all

# Force push (coordinate with team!)
git push origin --force --all
```

Or use [BFG Repo-Cleaner](https://rtyley.github.io/bfg-repo-cleaner/):

```bash
bfg --replace-text passwords.txt
```

### 3. Verify Removal

```bash
git log --all --full-history -- "test/support/cassettes/leaked.jsonl"
```

## Summary

1. **Use `redact_cassette` macro** for automatic, programmatic redaction
2. **Automatic redaction** handles common auth patterns by default
3. **Named redactors** provide consistency across your test suite
4. **Review cassettes** before committing (even with automatic redaction)
5. **Use environment variables** for secrets in tests
6. **Add pre-commit hooks** to catch leaks
7. **Rotate secrets** if leaked

For most projects, combine Reqord's built-in automatic redaction with the `redact_cassette` macro for application-specific sensitive data. This provides comprehensive protection without manual cassette editing.
