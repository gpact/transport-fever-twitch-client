defmodule TF2Client.Requests do
  @moduledoc false

  alias TF2Client.GameBridge
  alias TF2Client.RequestTracker

  def handle_chat_command({:help}, _sender, _chat) do
    {:reply,
     "Commands: !claim [company name], !town [company name], !line <carrier> <cargo>, !vehicle <carrier> <cargo>"}
  end

  def handle_chat_command({:claim, company_name}, sender, chat) do
    submit("COMPANY", sender, chat, %{company_name: company_name})
  end

  def handle_chat_command({:town, company_name}, sender, chat) do
    submit("TOWN", sender, chat, %{company_name: company_name})
  end

  def handle_chat_command({:line, carrier, cargo}, sender, chat) do
    submit("LINE", sender, chat, %{carrier: carrier, cargo: cargo})
  end

  def handle_chat_command({:vehicle, carrier, cargo}, sender, chat) do
    submit("VEHICLE", sender, chat, %{carrier: carrier, cargo: cargo})
  end

  def handle_chat_command(_other, _sender, _chat), do: :ignore

  defp submit(type, sender, chat, params) do
    params =
      params
      |> Enum.reject(fn {_k, v} -> is_nil(v) or v == "" end)
      |> Map.new()

    case GameBridge.submit(type, sender, params) do
      {:ok, order_id} ->
        RequestTracker.track(order_id, %{
          channel: chat,
          username: sender,
          type: type
        })

        {:reply, "@#{sender} queued #{type} request (#{order_id})"}

      {:error, :game_state_missing} ->
        {:reply,
         "@#{sender} the game state file is missing; start the game with the mod enabled so it can write gameState.json"}

      {:error, :save_uuid_missing} ->
        {:reply,
         "@#{sender} save_uuid not found yet; load a save with the mod enabled and wait for gameState.json to update"}

      {:error, {:file_error, reason}} ->
        {:reply, "@#{sender} couldn't write request files: #{reason}"}

      {:error, reason} ->
        {:reply, "@#{sender} couldn't queue request: #{inspect(reason)}"}
    end
  end
end

