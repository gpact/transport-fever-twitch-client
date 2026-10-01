defmodule TF2Client.Sim.Mod do
  @moduledoc false

  alias TF2Client.GameBridge

  def write_response(order_id, username, type, status, error_message \\ nil, extra \\ %{})
      when is_binary(order_id) and is_binary(username) and is_binary(type) and status in [:pending, :ok, :error] do
    completed = status != :pending
    error = if status == :error, do: error_message || "Simulated error", else: nil

    response =
      case {type, status} do
        {"SET_TOWN_CREATION_ENABLED", :ok} ->
          enabled = Map.get(extra, :enabled, read_order_enabled(order_id))
          %{"setting" => "townCreationEnabled", "enabled" => enabled}

        _ ->
          Map.get(extra, :response)
      end

    data = %{
      "username" => username,
      "type" => type,
      "completed" => completed,
      "error" => error,
      "response" => response
    }

    json = Jason.encode!(data)

    with :ok <- GameBridge.ensure_requests_dir() do
      File.write(GameBridge.response_json_path(order_id), json <> "\n")
    end
  end

  defp read_order_enabled(order_id) do
    case File.read(GameBridge.order_lua_path(order_id)) do
      {:ok, content} ->
        not String.contains?(content, "enabled = false")

      _ ->
        true
    end
  end
end
