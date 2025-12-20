defmodule TF2Client.ChatbotState do
  @moduledoc false

  use GenServer

  @name __MODULE__

  @default_channel_state %{enabled: false, paused: MapSet.new()}

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

  def pause(channel, command) when is_binary(channel) and is_atom(command) do
    channel = normalize_channel(channel)
    GenServer.call(@name, {:pause, channel, command})
  end

  def resume(channel, command) when is_binary(channel) and is_atom(command) do
    channel = normalize_channel(channel)
    GenServer.call(@name, {:resume, channel, command})
  end

  def paused?(channel, command) when is_binary(channel) and is_atom(command) do
    channel = normalize_channel(channel)
    GenServer.call(@name, {:paused?, channel, command})
  end

  def paused_commands(channel) when is_binary(channel) do
    channel = normalize_channel(channel)
    GenServer.call(@name, {:paused_commands, channel})
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
    channel_state = channel_state(state, channel)
    {:reply, channel_state.enabled, state}
  end

  def handle_call({:set_enabled, channel, enabled}, _from, state) do
    channel_state = channel_state(state, channel)
    updated = Map.put(channel_state, :enabled, enabled)
    {:reply, :ok, Map.put(state, channel, updated)}
  end

  def handle_call({:pause, channel, command}, _from, state) do
    channel_state = channel_state(state, channel)
    paused = MapSet.put(channel_state.paused, command)
    updated = %{channel_state | paused: paused}
    {:reply, :ok, Map.put(state, channel, updated)}
  end

  def handle_call({:resume, channel, command}, _from, state) do
    channel_state = channel_state(state, channel)
    paused = MapSet.delete(channel_state.paused, command)
    updated = %{channel_state | paused: paused}
    {:reply, :ok, Map.put(state, channel, updated)}
  end

  def handle_call({:paused?, channel, command}, _from, state) do
    channel_state = channel_state(state, channel)
    {:reply, MapSet.member?(channel_state.paused, command), state}
  end

  def handle_call({:paused_commands, channel}, _from, state) do
    channel_state = channel_state(state, channel)
    paused = MapSet.to_list(channel_state.paused)
    {:reply, Enum.sort_by(paused, &Atom.to_string/1), state}
  end

  defp normalize_channel(channel) when is_binary(channel) do
    channel =
      channel
      |> String.trim()
      |> String.downcase()

    String.trim_leading(channel, "#")
  end

  defp channel_state(state, channel) do
    case Map.get(state, channel) do
      %{} = channel_state -> channel_state
      enabled when is_boolean(enabled) -> %{enabled: enabled, paused: MapSet.new()}
      _ -> @default_channel_state
    end
  end
end
