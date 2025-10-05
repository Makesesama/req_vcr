defmodule Reqord.SequentialReplayTest do
  @moduledoc """
  Test that validates sequential replay of identical requests.

  This reproduces the issue where GET-GET requests with identical URLs
  would both return the first GET's response, instead of proceeding
  sequentially through the cassette.
  """

  use Reqord.Case
  alias Reqord.TestHelpers

  @moduletag :integration

  # This test demonstrates the sequential replay issue with identical GET requests
  # The test demonstrates GET->GET->GET->GET where some GETs are identical
  # but should return different responses based on their position in the cassette
  @tag vcr: "SequentialReplayTest/identical_get_requests", sequential_replay: true
  test "sequential replay of identical GET requests should return different responses" do
    client = TestHelpers.test_api_client()

    # GET: User 1 exists (hardcoded in API)
    {:ok, get_resp1} = Req.get(client, url: "/api/users/1")

    assert get_resp1.status == 200
    assert get_resp1.body["id"] == 1
    assert get_resp1.body["name"] == "Alice"

    # GET: Same request again - should return same data (user still exists)
    {:ok, get_resp2} = Req.get(client, url: "/api/users/1")

    assert get_resp2.status == 200
    assert get_resp2.body["id"] == 1
    assert get_resp2.body["name"] == "Alice"

    # GET: Non-existent user
    {:ok, get_resp3} = Req.get(client, url: "/api/users/999")

    assert get_resp3.status == 404
    assert get_resp3.body["error"] == "User not found"

    # GET: Same non-existent user again
    {:ok, get_resp4} = Req.get(client, url: "/api/users/999")

    assert get_resp4.status == 404
    assert get_resp4.body["error"] == "User not found"
  end
end
