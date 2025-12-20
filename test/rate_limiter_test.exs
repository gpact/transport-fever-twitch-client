defmodule TF2Client.RateLimiterTest do
  use ExUnit.Case, async: false

  alias TF2Client.RateLimiter

  setup do
    previous = Application.get_env(:tf2_client, :disable_rate_limits)
    RateLimiter.reset()

    on_exit(fn ->
      Application.put_env(:tf2_client, :disable_rate_limits, previous)
    end)

    :ok
  end

  test "enforces one-time rule" do
    key = {:user, "alice", :claim}

    assert :allow = RateLimiter.check(key, :once, 1_000)
    assert :deny = RateLimiter.check(key, :once, 1_001)
  end

  test "enforces cooldown rule" do
    key = {:user, "alice", :vehicles}
    rule = %{cooldown_seconds: 60}

    assert :allow = RateLimiter.check(key, rule, 1_000)
    assert :deny = RateLimiter.check(key, rule, 1_030)
    assert :allow = RateLimiter.check(key, rule, 1_060)
  end

  test "enforces cooldown + max per window" do
    key = {:user, "alice", :purchase_vehicle}

    rule = %{
      cooldown_seconds: 300,
      window_seconds: 3_600,
      max_in_window: 3
    }

    assert :allow = RateLimiter.check(key, rule, 1_000)
    assert :deny = RateLimiter.check(key, rule, 1_100)

    assert :allow = RateLimiter.check(key, rule, 1_300)
    assert :allow = RateLimiter.check(key, rule, 1_600)
    assert :deny = RateLimiter.check(key, rule, 1_900)

    assert :allow = RateLimiter.check(key, rule, 5_000)
  end

  test "allows everything when rate limiting is disabled" do
    Application.put_env(:tf2_client, :disable_rate_limits, true)
    key = {:user, "alice", :purchase_vehicle}

    assert :allow = RateLimiter.check(key, :once, 1_000)
    assert :allow = RateLimiter.check(key, :once, 1_001)
  end
end
