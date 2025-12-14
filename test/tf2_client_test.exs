defmodule TF2ClientTest do
  use ExUnit.Case
  doctest TF2Client

  test "greets the world" do
    assert TF2Client.hello() == :world
  end
end
