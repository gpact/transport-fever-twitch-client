defmodule TF2Client.Sim.Mod do
  @moduledoc false

  alias TF2Client.GameBridge

  def write_response(order_id, username, type, status, error_message \\ nil)
      when is_binary(order_id) and is_binary(username) and is_binary(type) and status in [:pending, :ok, :error] do
    completed = status != :pending
    error = if status == :error, do: error_message || "Simulated error", else: nil

    json = %{
      "username" => username,
      "type" => type,
      "completed" => completed,
      "error" => error
    }

    File.write(GameBridge.response_json_path(order_id), encode_json_object(json) <> "\n")
  end

  defp encode_json_object(map) when is_map(map) do
    keys = Map.keys(map)

    inner =
      keys
      |> Enum.sort()
      |> Enum.map(fn key ->
        value = Map.fetch!(map, key)
        ~s(  "#{escape_json_string(key)}": #{encode_json_value(value)})
      end)
      |> Enum.join(",\n")

    "{\n" <> inner <> "\n}"
  end

  defp encode_json_value(true), do: "true"
  defp encode_json_value(false), do: "false"
  defp encode_json_value(nil), do: "null"
  defp encode_json_value(value) when is_binary(value), do: ~s("#{escape_json_string(value)}")
  defp encode_json_value(value) when is_integer(value) or is_float(value), do: to_string(value)

  defp escape_json_string(str) do
    str
    |> String.replace("\\", "\\\\")
    |> String.replace("\"", "\\\"")
    |> String.replace("\n", "\\n")
    |> String.replace("\r", "\\r")
    |> String.replace("\t", "\\t")
  end
end

