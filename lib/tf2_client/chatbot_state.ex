defmodule TF2Client.ChatbotState do
  @moduledoc false

  use GenServer

  @name __MODULE__

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: @name)
  end

  def ensure_started do
    case Process.whereis(@name) do
      nil ->
        case start_link([]) do
          {:ok, _pid} -> :ok
          {:error, {:already_started, _pid}} -> :ok
          {:error, reason} -> raise "Failed to start ChatbotState: #{inspect(reason)}"
        end

      _pid ->
        :ok
    end
  end

  def reset do
    ensure_started()
    GenServer.call(@name, :reset)
  end

  def enable(channel) when is_binary(channel) do
    set_enabled(channel, true)
  end

  def disable(channel) when is_binary(channel) do
    set_enabled(channel, false)
  end

  def enabled?(channel) when is_binary(channel) do
    channel = normalize_channel(channel)
    GenServer.call(@name, {:enabled?, channel})
  end

  defp set_enabled(channel, enabled) when is_boolean(enabled) do
    channel = normalize_channel(channel)
    GenServer.call(@name, {:set_enabled, channel, enabled})
  end

  @impl GenServer
  def init(state), do: {:ok, state}

  @impl GenServer
  def handle_call(:reset, _from, _state) do
    {:reply, :ok, %{}}
  end

  def handle_call({:enabled?, channel}, _from, state) do
    {:reply, Map.get(state, channel, false), state}
  end

  def handle_call({:set_enabled, channel, enabled}, _from, state) do
    {:reply, :ok, Map.put(state, channel, enabled)}
  end

  defp normalize_channel(channel) when is_binary(channel) do
    channel =
      channel
      |> String.trim()
      |> String.downcase()

    String.trim_leading(channel, "#")
  end
end
