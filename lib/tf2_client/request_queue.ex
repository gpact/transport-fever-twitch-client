defmodule TF2Client.RequestQueue do
  @moduledoc false

  use GenServer

  require Logger

  alias TF2Client.GameBridge
  alias TF2Client.RequestTracker

  @name __MODULE__

  @default_delays_ms %{
    "COMPANY" => 0,
    "TOWN" => 5_000,
    "TOWN_RENAME" => 0,
    "LINE" => 0,
    "VEHICLE" => 0
  }

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: @name)
  end

  def submit(type, username, chat, params, save_uuid)
      when is_binary(type) and is_binary(username) and is_binary(chat) and is_map(params) and
             is_binary(save_uuid) do
    delay_ms = delay_ms_for(type)

    case delay_ms do
      0 -> submit_immediately(type, username, save_uuid, params)
      delay_ms -> enqueue_delayed(type, username, chat, params, save_uuid, delay_ms)
    end
  end

  @impl GenServer
  def init(_state) do
    {:ok, %{queue: :queue.new(), processing: false}}
  end

  @impl GenServer
  def handle_call({:enqueue, type, username, chat, params, save_uuid, delay_ms}, _from, state) do
    order_id = new_order_id()

    entry = %{
      order_id: order_id,
      type: type,
      username: username,
      chat: chat,
      params: params,
      save_uuid: save_uuid,
      delay_ms: delay_ms
    }

    queue = :queue.in(entry, state.queue)
    state = %{state | queue: queue}
    state = maybe_start_processing(state)

    {:reply, {:ok, order_id}, state}
  end

  @impl GenServer
  def handle_info(:process_next, state) do
    case :queue.out(state.queue) do
      {{:value, entry}, queue} ->
        state = %{state | queue: queue, processing: true}
        process_entry(entry)
        schedule_next(entry.delay_ms)
        {:noreply, state}

      {:empty, _queue} ->
        {:noreply, %{state | processing: false}}
    end
  end

  defp process_entry(entry) do
    case GameBridge.submit_with_order_id(
           entry.order_id,
           entry.type,
           entry.username,
           entry.save_uuid,
           entry.params
         ) do
      {:ok, _order_id} ->
        :ok

      {:error, reason} ->
        RequestTracker.untrack(entry.order_id)
        Logger.warning("Failed to write queued request #{entry.order_id}: #{inspect(reason)}")
    end
  end

  defp schedule_next(0) do
    send(self(), :process_next)
    :ok
  end

  defp schedule_next(delay_ms) when is_integer(delay_ms) and delay_ms > 0 do
    Process.send_after(self(), :process_next, delay_ms)
    :ok
  end

  defp schedule_next(_delay_ms) do
    send(self(), :process_next)
    :ok
  end

  defp maybe_start_processing(%{processing: false} = state) do
    send(self(), :process_next)
    %{state | processing: true}
  end

  defp maybe_start_processing(state), do: state

  defp delay_ms_for(type) when is_binary(type) do
    type = String.upcase(type)

    delays =
      case Application.get_env(:tf2_client, :request_queue_delays_ms) do
        %{} = delays -> delays
        _ -> env_delay_overrides()
      end

    Map.get(delays, type, Map.get(@default_delays_ms, type, 0))
  end

  defp enqueue_delayed(type, username, chat, params, save_uuid, delay_ms)
       when is_integer(delay_ms) and delay_ms > 0 do
    GenServer.call(@name, {:enqueue, type, username, chat, params, save_uuid, delay_ms})
  end

  defp submit_immediately(type, username, save_uuid, params) do
    order_id = new_order_id()

    case GameBridge.submit_with_order_id(order_id, type, username, save_uuid, params) do
      {:ok, _order_id} -> {:ok, order_id}
      {:error, reason} -> {:error, reason}
    end
  end

  defp env_delay_overrides do
    case System.get_env("TF2_REQUEST_QUEUE_DELAYS_MS") do
      nil -> %{}
      "" -> %{}
      value -> parse_delay_overrides(value)
    end
  end

  defp parse_delay_overrides(raw) when is_binary(raw) do
    raw
    |> String.split([",", " "], trim: true)
    |> Enum.reduce(%{}, fn entry, acc ->
      case String.split(entry, "=", parts: 2) do
        [type, delay_raw] ->
          type = String.trim(type)
          delay_raw = String.trim(delay_raw)

          case Integer.parse(delay_raw) do
            {delay_ms, ""} when delay_ms >= 0 ->
              Map.put(acc, String.upcase(type), delay_ms)

            _ ->
              acc
          end

        _ ->
          acc
      end
    end)
  end

  defp new_order_id do
    :crypto.strong_rand_bytes(16)
    |> Base.encode16(case: :lower)
  end
end
