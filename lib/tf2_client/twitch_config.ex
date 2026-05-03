defmodule TF2Client.TwitchConfig do
  @moduledoc false

  alias TF2Client.Twitch.TokenRefresher

  def from_env do
    enabled =
      case System.get_env("TF2_ENABLE_TWITCH_BOT") do
        nil -> true
        value -> value not in ["0", "false", "FALSE", "no", "NO"]
      end

    if not enabled do
      {:error, "TF2_ENABLE_TWITCH_BOT disabled"}
    else
      with {:ok, user} <- fetch_env("TWITCH_BOT_USER"),
           {:ok, pass} <- fetch_irc_password(),
           {:ok, channels} <- fetch_env_list("TWITCH_CHANNELS") do
        mod_channels = env_list("TWITCH_MOD_CHANNELS")
        debug = env_bool("TWITCH_DEBUG", false)

        {:ok,
         [
           bot: TF2Client.Bot,
           user: String.downcase(user),
           pass: pass,
           channels: Enum.map(channels, &String.downcase/1),
           mod_channels: Enum.map(mod_channels, &String.downcase/1),
           debug: debug
         ]}
      else
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp fetch_irc_password do
    case System.get_env("TWITCH_BOT_OAUTH") do
      value when is_binary(value) and value != "" ->
        {:ok, ensure_oauth_prefix(value)}

      _ ->
        case TokenRefresher.irc_password() do
          {:ok, pass} -> {:ok, pass}
          {:error, :missing_tokens} -> {:error, "missing Twitch OAuth tokens; run oauth.bootstrap"}
        end
    end
  end

  defp ensure_oauth_prefix("oauth:" <> _rest = value), do: value
  defp ensure_oauth_prefix(value) when is_binary(value), do: "oauth:" <> value

  defp fetch_env(key) do
    case System.get_env(key) do
      nil -> {:error, "missing env var #{key}"}
      "" -> {:error, "missing env var #{key}"}
      value -> {:ok, value}
    end
  end

  defp fetch_env_list(key) do
    case env_list(key) do
      [] -> {:error, "missing env var #{key} (comma-separated list)"}
      list -> {:ok, list}
    end
  end

  defp env_list(key) do
    key
    |> System.get_env()
    |> case do
      nil ->
        []

      value ->
        value
        |> String.split([",", " "], trim: true)
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))
    end
  end

  defp env_bool(key, default) do
    case System.get_env(key) do
      nil -> default
      "1" -> true
      "true" -> true
      "TRUE" -> true
      "yes" -> true
      "YES" -> true
      "0" -> false
      "false" -> false
      "FALSE" -> false
      "no" -> false
      "NO" -> false
      _ -> default
    end
  end
end
