ExUnit.start()

# Exclude integration tests by default - they require the test API to be running
ExUnit.configure(exclude: [:integration])

# Load test helpers
Code.require_file("support/test_helpers.ex", __DIR__)
