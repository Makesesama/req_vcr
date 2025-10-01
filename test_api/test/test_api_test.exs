defmodule TestApiTest do
  use ExUnit.Case
  doctest TestApi

  test "greets the world" do
    assert TestApi.hello() == :world
  end
end
