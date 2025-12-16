defmodule TF2Client.Response do
  @moduledoc false

  def parse(json) when is_binary(json) do
    %{
      username: extract_string(json, "username"),
      type: extract_string(json, "type"),
      completed: extract_bool(json, "completed"),
      error: extract_string(json, "error")
    }
    |> then(&{:ok, &1})
  end

  def format(%{username: username, type: type, completed: false, error: nil})
      when is_binary(username) and is_binary(type) do
    "@#{username} your #{type} request is pending"
  end

  def format(%{username: username, type: type, completed: _completed, error: error})
      when is_binary(username) and is_binary(type) and is_binary(error) do
    "@#{username} your #{type} request failed: #{error}"
  end

  def format(%{username: username, type: type, completed: true, error: nil})
      when is_binary(username) and is_binary(type) do
    "@#{username} your #{type} request completed"
  end

  def format(_), do: nil

  defp extract_bool(json, key) do
    case Regex.run(~r/"#{Regex.escape(key)}"\s*:\s*(true|false)/, json) do
      [_, "true"] -> true
      [_, "false"] -> false
      _ -> false
    end
  end

  defp extract_string(json, key) do
    cond do
      Regex.match?(~r/"#{Regex.escape(key)}"\s*:\s*null/, json) ->
        nil

      true ->
        case Regex.run(~r/"#{Regex.escape(key)}"\s*:\s*"((?:\\.|[^"\\])*)"/, json) do
          [_, raw] -> unescape_json_string(raw)
          _ -> nil
        end
    end
  end

  defp unescape_json_string(raw) do
    raw
    |> String.replace("\\\\", "\\")
    |> String.replace("\\n", "\n")
    |> String.replace("\\r", "\r")
    |> String.replace("\\t", "\t")
    |> String.replace("\\\"", "\"")
  end
end

