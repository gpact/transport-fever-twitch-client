defmodule TF2Client.Requests do
  @moduledoc false

  @available_command_examples TF2Client.Commands.examples()

  @carrier_types Enum.map(TF2Client.Game.carrier_types(), &to_string/1)

  @cargo_types Enum.map(TF2Client.Game.cargo_types(), &to_string/1)

  require Logger

  alias TF2Client.GameBridge
  alias TF2Client.RequestTracker

  def handle_chat_command({:help}, _sender, _chat) do
    {:reply, "Commands: #{Enum.join(@available_command_examples, " • ")}"}
  end

  def handle_chat_command({:carriers}, _sender, _chat) do
    {:reply, "Carrier types: #{Enum.join(@carrier_types, ", ")}"}
  end

  def handle_chat_command({:cargo}, _sender, _chat) do
    {:reply, "Cargo types: #{Enum.join(@cargo_types, ", ")}"}
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
    params = normalize_params(params)

    case GameBridge.submit(type, sender, params) do
      {:ok, order_id} ->
        RequestTracker.track(order_id, %{
          channel: chat,
          username: sender,
          type: type
        })

        {:reply, queued_message(type, sender, params)}

      {:error, :game_state_missing} ->
        {:reply,
         "@#{sender} I can't reach the game right now. Start Transport Fever 2 with the integration enabled and load a save, then try again."}

      {:error, :save_uuid_missing} ->
        {:reply,
         "@#{sender} the game isn't ready yet. Load a save (with the integration enabled) and try again in a few seconds."}

      {:error, :game_state_invalid} ->
        {:reply,
         "@#{sender} the game isn't ready yet. Load a save (with the integration enabled) and try again in a few seconds."}

      {:error, {:file_error, reason}} ->
        Logger.warning("Failed to submit request to game files: #{inspect(reason)}")
        {:reply, "@#{sender} I couldn't send that to the game due to a setup issue. Please try again in a moment."}

      {:error, reason} ->
        Logger.warning("Failed to submit request: #{inspect(reason)}")
        {:reply, "@#{sender} something went wrong on my side. Please try again in a moment."}
    end
  end

  defp queued_message(type, sender, params) when is_binary(type) and is_binary(sender) and is_map(params) do
    action = action_description(type, params)
    "@#{sender} got it! I'll try to #{action}."
  end

  defp normalize_params(params) when is_map(params) do
    params
    |> Enum.reject(fn {_k, v} -> is_nil(v) or v == "" end)
    |> Map.new()
  end

  defp action_description("COMPANY", %{company_name: name}) when is_binary(name) and name != "" do
    ~s(claim/create your company "#{name}")
  end

  defp action_description("COMPANY", _params), do: "claim/create your company"

  defp action_description("TOWN", %{company_name: name}) when is_binary(name) and name != "" do
    ~s(get you a town "#{name}")
  end

  defp action_description("TOWN", _params), do: "get you a town"

  defp action_description("LINE", %{carrier: carrier, cargo: cargo})
       when is_binary(carrier) and carrier != "" and is_binary(cargo) and cargo != "" do
    carrier = String.downcase(carrier)
    cargo = String.downcase(cargo)
    "set up a #{carrier} line for #{cargo}"
  end

  defp action_description("LINE", _params), do: "set up a transport line"

  defp action_description("VEHICLE", %{carrier: carrier, cargo: cargo})
       when is_binary(carrier) and carrier != "" and is_binary(cargo) and cargo != "" do
    carrier = String.downcase(carrier)
    cargo = String.downcase(cargo)
    "add a #{carrier} vehicle for #{cargo}"
  end

  defp action_description("VEHICLE", _params), do: "add a vehicle"

  defp action_description(_type, _params), do: "do that"
end
