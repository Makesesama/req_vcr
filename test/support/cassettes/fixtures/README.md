# Test Fixtures

This directory contains permanent test cassettes that should be preserved across test runs.

These cassettes are used for:
- JSONL format validation tests
- Other library functionality tests that need stable cassette data

Unlike the temporary cassettes created during unit tests, files in this directory are:
- **Committed to git**
- **Not cleaned up** after test runs
- **Safe to reference** in tests that need consistent data

To add a new permanent test cassette, place it in this directory and update the test cleanup logic if needed.