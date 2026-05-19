defmodule TF2Client.RequestsTest do
  use ExUnit.Case, async: false

  alias TF2Client.RateLimiter
  alias TF2Client.Requests

  setup do
    previous = Application.get_env(:tf2_client, :disable_rate_limits)
    RateLimiter.reset()

    on_exit(fn ->
      Application.put_env(:tf2_client, :disable_rate_limits, previous)
    end)

    :ok
  end

  test "replies when a user hits a vehicle cooldown" do
    key = {:user, "alice", :purchase_vehicle}

    rule = %{
      cooldown_seconds: 5 * 60,
      window_seconds: 60 * 60,
      max_in_window: 3
    }

    assert :allow = RateLimiter.check(key, rule)

    assert {:reply, "@alice !vehicle is on cooldown for you for the next 5 minutes."} =
             Requests.handle_chat_command({:vehicle, "RAIL", "PASSENGERS"}, "alice", "somechannel")
  end

  test "replies when a user hits a stats cooldown" do
    key = {:user, "alice", :vehicles_owned}
    rule = %{cooldown_seconds: 60}

    assert :allow = RateLimiter.check(key, rule)

    assert {:reply, "@alice !vehicles is on cooldown for you for the next 1 minute."} =
             Requests.handle_chat_command({:vehicles_owned}, "alice", "somechannel")
  end

  test "replies when rank is on global cooldown" do
    key = {:global, :profit_rankings}
    rule = %{cooldown_seconds: 60}

    assert :allow = RateLimiter.check(key, rule)

    assert {:reply, "@bob !rank is on cooldown for everyone for the next 1 minute."} =
             Requests.handle_chat_command({:profit_rankings}, "bob", "somechannel")
  end
end
