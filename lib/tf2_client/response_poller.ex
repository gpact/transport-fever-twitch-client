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
  def init(state) do
    schedule_tick()
    {:ok, state}
  end

  @impl GenServer
  def handle_info(:tick, state) do
    handle_tick()
    schedule_tick()
    {:noreply, state}
  end

  defp schedule_tick do
    Process.send_after(self(), :tick, @interval_ms)
  end

  defp handle_tick do
    for order_id <- RequestTracker.pending_ids() do
      with %{channel: channel} <- RequestTracker.get(order_id),
           response_path <- GameBridge.response_json_path(order_id),
           true <- File.exists?(response_path),
           {:ok, json} <- File.read(response_path),
           {:ok, parsed} <- Response.parse(json),
           message when is_binary(message) <- Response.format(parsed) do
        maybe_send(channel, message)
        File.rm(response_path)

        if parsed.completed do
          RequestTracker.untrack(order_id)
          File.rm(GameBridge.order_lua_path(order_id))
        else
          :ok
        end
      else
        _ -> :noop
      end
    end
  end

  defp maybe_send(channel, message) when is_binary(channel) and is_binary(message) do
    sender = Application.get_env(:tf2_client, :chat_sender, TF2Client.Chat.TMI)

    if sender == TF2Client.Chat.TMI and not ChatbotState.enabled?(channel) do
      :ok
    else
      Chat.send(channel, message)
    end
  end
end
