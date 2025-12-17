defmodule TF2Client.Sim.Mod do
  @moduledoc false

  alias TF2Client.GameBridge

  def write_response(order_id, username, type, status, error_message \\ nil)
      when is_binary(order_id) and is_binary(username) and is_binary(type) and status in [:pending, :ok, :error] do
    completed = status != :pending
    error = if status == :error, do: error_message || "Simulated error", else: nil

    data = %{
      "username" => username,
      "type" => type,
      "completed" => completed,
      "error" => error
    }

    json = Jason.encode!(data)
    File.write(GameBridge.response_json_path(order_id), json <> "\n")
  end
end
