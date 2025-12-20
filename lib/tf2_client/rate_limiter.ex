defmodule TF2Client.RateLimiter do
  @moduledoc false

  require Logger

  @table __MODULE__

  def check(key, rule) do
    case disabled?() do
      true ->
        :allow

      false ->
        now = System.os_time(:second)
        check(key, rule, now)
    end
  end

  def check(key, rule, now) when is_integer(now) do
    case disabled?() do
      true ->
        :allow

      false ->
        check_rule(key, rule, now)
    end
  end

  defp check_rule(key, rule, now) when is_integer(now) do
    ensure_table()

    case rule do
      :once ->
        check_once(key, now)

      %{cooldown_seconds: cooldown_seconds, window_seconds: window_seconds, max_in_window: max_in_window}
      when is_integer(cooldown_seconds) and cooldown_seconds >= 0 and
             is_integer(window_seconds) and window_seconds > 0 and
             is_integer(max_in_window) and max_in_window > 0 ->
        check_cooldown_and_window(key, cooldown_seconds, window_seconds, max_in_window, now)

      %{cooldown_seconds: cooldown_seconds}
      when is_integer(cooldown_seconds) and cooldown_seconds >= 0 ->
        check_cooldown_only(key, cooldown_seconds, now)

      _ ->
        Logger.warning("Invalid rate limit rule for #{inspect(key)}: #{inspect(rule)}")
        :allow
    end
  end

  def reset do
    case :ets.whereis(@table) do
      :undefined -> :ok
      _ -> :ets.delete_all_objects(@table)
    end
  end

  defp check_once(key, now) do
    case lookup_timestamps(key) do
      [] ->
        put_timestamps(key, [now])
        :allow

      [_ | _] ->
        :deny
    end
  end

  defp check_cooldown_only(key, cooldown_seconds, now) do
    case lookup_timestamps(key) do
      [last | _] when is_integer(last) and now - last < cooldown_seconds ->
        :deny

      _timestamps ->
        put_timestamps(key, [now])
        :allow
    end
  end

  defp check_cooldown_and_window(key, cooldown_seconds, window_seconds, max_in_window, now) do
    timestamps = lookup_timestamps(key)

    timestamps =
      Enum.filter(timestamps, fn ts ->
        is_integer(ts) and ts > now - window_seconds
      end)

    case timestamps do
      [last | _] when now - last < cooldown_seconds ->
        :deny

      _ ->
        if length(timestamps) >= max_in_window do
          :deny
        else
          put_timestamps(key, [now | timestamps])
          :allow
        end
    end
  end

  defp lookup_timestamps(key) do
    case :ets.lookup(@table, key) do
      [{^key, timestamps}] when is_list(timestamps) -> timestamps
      _ -> []
    end
  end

  defp put_timestamps(key, timestamps) when is_list(timestamps) do
    :ets.insert(@table, {key, timestamps})
  end

  defp ensure_table do
    case :ets.whereis(@table) do
      :undefined ->
        try do
          :ets.new(@table, [
            :named_table,
            :public,
            :set,
            {:read_concurrency, true},
            {:write_concurrency, true}
          ])
        rescue
          ArgumentError -> :ok
        end

        :ok

      _ ->
        :ok
    end
  end

  defp disabled? do
    case Application.get_env(:tf2_client, :disable_rate_limits) do
      true -> true
      false -> false
      nil -> env_disabled?()
      value -> truthy?(value)
    end
  end

  defp env_disabled? do
    case System.get_env("TF2_DISABLE_RATE_LIMITS") do
      nil -> false
      value -> truthy?(value)
    end
  end

  defp truthy?(value) do
    case value do
      true -> true
      1 -> true
      "1" -> true
      "true" -> true
      "TRUE" -> true
      "yes" -> true
      "YES" -> true
      "on" -> true
      "ON" -> true
      _ -> false
    end
  end
end
