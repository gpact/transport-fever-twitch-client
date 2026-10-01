defmodule TF2Client.Response do
  @moduledoc false

  def parse(json) when is_binary(json) do
    with {:ok, %{} = decoded} <- Jason.decode(json) do
      username = normalize_optional_string(Map.get(decoded, "username"))
      type = normalize_optional_string(Map.get(decoded, "type"))
      error = normalize_optional_string(Map.get(decoded, "error"))
      completed = Map.get(decoded, "completed") == true
      response = Map.get(decoded, "response")

      {:ok,
       %{
         username: username,
         type: type,
         completed: completed,
         error: error,
         response: response
       }}
    else
      _ -> {:error, :invalid_json}
    end
  end

  def format(%{
        username: username,
        type: type,
        completed: true,
        error: nil,
        response: response
      })
      when is_binary(username) and is_binary(type) and is_map(response) do
    case toggle_response_status(type, response) do
      {label, enabled} -> "@#{username} #{label} is now #{enabled_label(enabled)}"
      nil -> "@#{username} your #{type} request completed"
    end
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

  defp toggle_response_status(_type, %{"label" => label, "enabled" => enabled})
       when is_binary(label) and is_boolean(enabled) do
    case String.trim(label) do
      "" -> nil
      label -> {label, enabled}
    end
  end

  defp toggle_response_status(_type, %{"setting" => setting, "enabled" => enabled})
       when is_binary(setting) and is_boolean(enabled) do
    case humanize_setting(setting) do
      "" -> nil
      label -> {label, enabled}
    end
  end

  defp toggle_response_status(_type, _response), do: nil

  defp enabled_label(true), do: "enabled"
  defp enabled_label(false), do: "disabled"

  defp humanize_setting(setting) do
    setting
    |> String.replace(~r/[_-]?enabled$/i, "")
    |> String.replace(~r/([a-z0-9])([A-Z])/, "\\1 \\2")
    |> String.replace(["_", "-"], " ")
    |> String.trim()
    |> String.downcase()
  end

  defp normalize_optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_optional_string(_), do: nil
end
