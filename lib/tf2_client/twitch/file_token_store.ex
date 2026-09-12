defmodule TF2Client.Twitch.FileTokenStore do
  @moduledoc false

  @behaviour TF2Client.Twitch.TokenStore

  @tokens_filename "twitch_tokens.json"
  @app_dir "tf2_client"

  @impl true
  def load do
    path = tokens_path()

    case File.read(path) do
      {:ok, json} ->
        parse_tokens(json)

      {:error, :enoent} ->
        :error

      {:error, _reason} ->
        :error
    end
  end

  @impl true
  def save(%{access_token: access_token, refresh_token: refresh_token, expires_at: expires_at})
      when is_binary(access_token) and is_binary(refresh_token) and is_integer(expires_at) do
    path = tokens_path()

    data = %{
      "access_token" => access_token,
      "refresh_token" => refresh_token,
      "expires_at" => expires_at
    }

    json = Jason.encode!(data)
    write_tokens_file!(path, json <> "\n")
  end

  def save(_other), do: :ok

  @impl true
  def delete do
    File.rm(tokens_path())
    :ok
  end

  defp parse_tokens(json) when is_binary(json) do
    case Jason.decode(json) do
      {:ok, %{} = decoded} ->
        access_token = decoded |> Map.get("access_token") |> normalize_optional_string()
        refresh_token = decoded |> Map.get("refresh_token") |> normalize_optional_string()
        expires_at = normalize_integer(Map.get(decoded, "expires_at"))

        if is_binary(access_token) and is_binary(refresh_token) and is_integer(expires_at) do
          {:ok, %{access_token: access_token, refresh_token: refresh_token, expires_at: expires_at}}
        else
          :error
        end

      _ ->
        :error
    end
  end

  defp tokens_path do
    Path.join(tokens_dir(), @tokens_filename)
  end

  defp tokens_dir do
    home = System.user_home!()
    Path.join([home, ".config", @app_dir])
  end

  defp write_tokens_file!(path, contents) when is_binary(path) and is_binary(contents) do
    dir = Path.dirname(path)
    File.mkdir_p!(dir)
    maybe_chmod(dir, 0o700)

    tmp_path = path <> ".tmp"
    File.write!(tmp_path, contents)
    maybe_chmod(tmp_path, 0o600)
    File.rename!(tmp_path, path)
    :ok
  end

  defp maybe_chmod(path, mode) when is_binary(path) and is_integer(mode) do
    case :os.type() do
      {:win32, _} -> :ok
      _ -> File.chmod(path, mode)
    end

    :ok
  end

  defp normalize_integer(value) when is_integer(value), do: value

  defp normalize_integer(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {parsed, ""} -> parsed
      _ -> nil
    end
  end

  defp normalize_integer(_), do: nil

  defp normalize_optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_optional_string(_), do: nil
end
