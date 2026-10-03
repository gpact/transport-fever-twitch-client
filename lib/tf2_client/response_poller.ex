defmodule TF2Client.ResponsePoller do
  @moduledoc false

  use GenServer

  alias TF2Client.GameBridge
  alias TF2Client.RequestTracker
  alias TF2Client.Response
  alias TF2Client.Chat
  alias TF2Client.ChatbotState

  @interval_ms 1_000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl GenServer
  def init(_state) do
    recovered_requests = recover_requests()
    schedule_tick()
    {:ok, %{recovered_requests: recovered_requests}}
  end

  @impl GenServer
  def handle_info(:tick, state) do
    recovered_requests = Enum.reject(state.recovered_requests, &acknowledge_recovered_request/1)
    handle_tick()
    schedule_tick()
    {:noreply, %{state | recovered_requests: recovered_requests}}
  end

  # Snapshot existing queues at startup: newly submitted requests use RequestTracker.
  # Channel routing is not persisted, so recovered outcomes are cleaned without chat replay.
  defp recover_requests do
    GameBridge.requests_dir()
    |> Path.join("requests_*.txt")
    |> Path.wildcard()
    |> Enum.flat_map(&recover_queue/1)
  end

  defp recover_queue(path) do
    with [_, save_uuid] <- Regex.run(~r/\Arequests_([A-Za-z0-9_-]+)\.txt\z/, Path.basename(path)),
         {:ok, contents} <- File.read(path) do
      contents
      |> String.split("\n", trim: true)
      |> Enum.map(&{&1, save_uuid})
    else
      _ -> []
    end
  end

  defp acknowledge_recovered_request({order_id, save_uuid}) do
    case RequestTracker.get(order_id) do
      nil -> cleanup_recovered_response(order_id, save_uuid)
      _tracked -> true
    end
  end

  defp cleanup_recovered_response(order_id, save_uuid) do
    response_path = GameBridge.response_json_path(order_id)

    with {:ok, json} <- File.read(response_path),
         {:ok, %{completed: true}} <- Response.parse(json),
         :ok <- GameBridge.complete_request(order_id, save_uuid) do
      File.rm(GameBridge.order_lua_path(order_id))
      File.rm(response_path)
      true
    else
      _ -> false
    end
  end

  defp schedule_tick do
    Process.send_after(self(), :tick, @interval_ms)
  end

  defp handle_tick do
    case GameBridge.ensure_requests_dir() do
      :ok -> poll_pending_responses()
      {:error, _reason} -> :noop
    end
  end

  defp poll_pending_responses do
    for order_id <- RequestTracker.pending_ids() do
      with %{channel: channel} = tracked <- RequestTracker.get(order_id),
           response_path <- GameBridge.response_json_path(order_id),
           true <- File.exists?(response_path),
           {:ok, json} <- File.read(response_path),
           {:ok, parsed} <- Response.parse(json),
           parsed <- fill_tracked_request_data(parsed, tracked),
           message when is_binary(message) <- Response.format(parsed) do
        case acknowledge_response(order_id, parsed, tracked) do
          :ok ->
            maybe_send(channel, message, parsed.type)
            File.rm(response_path)

          {:error, _reason} ->
            :noop
        end
      else
        _ -> :noop
      end
    end
  end

  defp acknowledge_response(order_id, %{completed: true}, tracked) do
    with :ok <- GameBridge.complete_request(order_id, Map.get(tracked, :save_uuid)) do
      File.rm(GameBridge.order_lua_path(order_id))
      RequestTracker.untrack(order_id)
      :ok
    end
  end

  defp acknowledge_response(_order_id, _parsed, _tracked), do: :ok

  defp fill_tracked_request_data(parsed, tracked) when is_map(parsed) and is_map(tracked) do
    parsed
    |> put_tracked_string(:username, Map.get(tracked, :username))
    |> put_tracked_string(:type, Map.get(tracked, :type))
  end

  defp put_tracked_string(parsed, key, value) when is_binary(value) do
    case Map.get(parsed, key) do
      nil -> Map.put(parsed, key, value)
      "" -> Map.put(parsed, key, value)
      _existing -> parsed
    end
  end

  defp put_tracked_string(parsed, _key, _value), do: parsed

  defp maybe_send(channel, message, type) when is_binary(channel) and is_binary(message) do
    case should_send?(channel, type) do
      true -> Chat.send(channel, message)
      false -> :ok
    end
  end

  defp should_send?(_channel, "SET_TOWN_CREATION_ENABLED"), do: true

  defp should_send?(channel, _type) do
    case Application.get_env(:tf2_client, :chat_sender, TF2Client.Chat.TMI) do
      TF2Client.Chat.TMI -> ChatbotState.enabled?(channel)
      _custom_sender -> true
    end
  end
end
