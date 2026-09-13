defmodule TF2Client.TwitchConfig do
  @moduledoc false

  alias TF2Client.Config
  alias TF2Client.Twitch.OAuthBootstrap
  alias TF2Client.Twitch.TokenRefresher

  def from_env do
    load()
  end

  def load do
    case Config.load() do
      {:ok, %Config{} = config} ->
        from_config(config)

      {:error, reason} ->
        {:error, reason}
    end
  end

  def from_config(%Config{enable_bot: false}) do
    {:error, "TF2_ENABLE_TWITCH_BOT disabled"}
  end

  def from_config(%Config{} = config) do
    with {:ok, user} <- validate_user(config.bot_user),
         {:ok, channels} <- validate_channels(config.channels),
         {:ok, pass} <- fetch_irc_password(config) do
      {:ok,
       [
         bot: TF2Client.Bot,
         user: String.downcase(user),
         pass: pass,
         channels: Enum.map(channels, &String.downcase/1),
         mod_channels: Enum.map(config.mod_channels, &String.downcase/1),
         debug: config.debug
       ]}
    end
  end

  defp validate_user(user) when is_binary(user) and user != "", do: {:ok, user}
  defp validate_user(_), do: {:error, "missing bot username (configure in config.json or TWITCH_BOT_USER)"}

  defp validate_channels([_first | _rest] = channels), do: {:ok, channels}
  defp validate_channels(_), do: {:error, "missing channels (configure in config.json or TWITCH_CHANNELS)"}

  defp fetch_irc_password(%Config{bot_oauth: oauth}) when is_binary(oauth) and oauth != "" do
    {:ok, ensure_oauth_prefix(oauth)}
  end

  defp fetch_irc_password(%Config{} = config) do
    case TokenRefresher.irc_password() do
      {:ok, pass} ->
        {:ok, pass}

      {:error, :missing_tokens} ->
        maybe_auto_bootstrap(config)
    end
  end

  defp maybe_auto_bootstrap(%Config{} = _config) do
    case auto_bootstrap_allowed?() do
      true ->
        IO.puts("""
        ======================================================
         Twitch Authorization Required
        ======================================================
         Opening browser to authorize with Twitch...
        """)

        case OAuthBootstrap.bootstrap!() do
          :ok ->
            IO.puts("Twitch authorization complete! Connecting to chat...\n")
            TokenRefresher.irc_password()

          :already_authorized ->
            TokenRefresher.irc_password()
        end

      false ->
        {:error, "missing Twitch OAuth tokens; run oauth.bootstrap"}
    end
  end

  defp auto_bootstrap_allowed? do
    case test_env?() do
      true ->
        false

      false ->
        System.get_env("TF2_DISABLE_AUTO_AUTH") not in ["1", "true", "TRUE"]
    end
  end

  defp test_env? do
    Code.ensure_loaded?(Mix) and function_exported?(Mix, :env, 0) and Mix.env() == :test
  end

  defp ensure_oauth_prefix("oauth:" <> _rest = value), do: value
  defp ensure_oauth_prefix(value) when is_binary(value), do: "oauth:" <> value
end
