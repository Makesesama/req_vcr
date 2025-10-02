defmodule Reqord.ExampleAPITest do
  @moduledoc """
  Example tests using Reqord with a local test API.

  These tests demonstrate Reqord's recording and replay functionality.

  ## Setup

  First, start the test API server:

      cd test_api && mix run --no-halt

  Then record cassettes:

      REQORD=all mix test test/example_api_test.exs

  Finally, run tests in replay mode (no network calls):

      mix test test/example_api_test.exs
  """

  use Reqord.Case

  @moduletag :example_api

  defp default_stub_name, do: Reqord.ExampleAPIStub

  test "fetches list of users with authentication" do
    client =
      Req.new(
        plug: {Req.Test, Reqord.ExampleAPIStub},
        headers: [{"authorization", "Bearer test-token"}]
      )

    {:ok, response} = Req.get(client, url: "http://localhost:4001/api/users")

    assert response.status == 200
    assert is_list(response.body)
    assert length(response.body) == 2

    first_user = List.first(response.body)
    assert first_user["id"] == 1
    assert first_user["name"] == "Alice"
    assert first_user["email"] == "alice@example.com"
  end

  test "fetches a single user" do
    client =
      Req.new(
        plug: {Req.Test, Reqord.ExampleAPIStub},
        headers: [{"authorization", "Bearer test-token"}]
      )

    {:ok, response} = Req.get(client, url: "http://localhost:4001/api/users/1")

    assert response.status == 200
    assert response.body["id"] == 1
    assert response.body["name"] == "Alice"
    assert response.body["email"] == "alice@example.com"
  end

  test "creates a new user" do
    client =
      Req.new(
        plug: {Req.Test, Reqord.ExampleAPIStub},
        headers: [{"authorization", "Bearer test-token"}]
      )

    {:ok, response} =
      Req.post(client,
        url: "http://localhost:4001/api/users",
        json: %{name: "Charlie", email: "charlie@example.com"}
      )

    assert response.status == 201
    assert response.body["id"] == 3
    assert response.body["name"] == "Charlie"
    assert response.body["email"] == "charlie@example.com"
  end

  test "returns 401 without authentication" do
    client = Req.new(plug: {Req.Test, Reqord.ExampleAPIStub})

    {:ok, response} = Req.get(client, url: "http://localhost:4001/api/users")

    assert response.status == 401
    assert response.body["error"] == "Unauthorized"
  end
end
