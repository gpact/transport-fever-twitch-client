defmodule TF2Client.Response do
  @moduledoc false

  def parse(json) when is_binary(json) do
    with {:ok, %{} = decoded} <- Jason.decode(json) do
      username = decoded |> Map.get("username") |> normalize_optional_string()
      type = decoded |> Map.get("type") |> normalize_optional_string()
      error = decoded |> Map.get("error") |> normalize_optional_string()
      completed = Map.get(decoded, "completed") == true

      {:ok,
       %{
         username: username,
         type: type,
         completed: completed,
         error: error
       }}
    else
      _ -> {:error, :invalid_json}
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

  defp normalize_optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_optional_string(_), do: nil
end
