defmodule TF2Client.RateLimiter do
  @moduledoc false

  require Logger

  @table __MODULE__

  def check(key, rule) do
    now = System.os_time(:second)
    check(key, rule, now)
  end

  def check(key, rule, now) when is_integer(now) do
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
end
