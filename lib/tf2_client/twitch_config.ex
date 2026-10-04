defmodule TF2Client.TwitchConfig do
  @moduledoc false

  alias TF2Client.Config
  alias TF2Client.Twitch.OAuthBootstrap
  alias TF2Client.Twitch.TokenStore
  alias TF2Client.Twitch.TokenValidator
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

  def from_config(config, request \\ &Finch.request/2)

  def from_config(%Config{enable_bot: false}, _request) do
    {:error, "TF_ENABLE_TWITCH_BOT disabled"}
  end

  def from_config(%Config{} = config, request) do
    with {:ok, user} <- validate_user(config.bot_user),
         {:ok, channels} <- validate_channels(config.channels),
         {:ok, pass} <- fetch_irc_password(config, request) do
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

  defp fetch_irc_password(%Config{bot_oauth: oauth, bot_user: user}, request)
       when is_binary(oauth) and oauth != "" do
    password = ensure_oauth_prefix(oauth)

    case TokenValidator.validate(password, user, request) do
      :ok -> {:ok, password}
      {:error, reason} -> {:error, authentication_error(reason, user) <> " Update your manual OAuth token in setup."}
    end
  end

  defp fetch_irc_password(%Config{} = config, request) do
    case TokenRefresher.irc_password() do
      {:ok, password} -> validate_saved_password(password, config, request)
      {:error, :missing_tokens} -> authorize_and_validate(config, request)
    end
  end

  defp validate_saved_password(password, %Config{bot_user: user} = config, request) do
    case TokenValidator.validate(password, user, request) do
      :ok ->
        {:ok, password}

      {:error, reason} when reason in [:invalid_token, :missing_chat_scopes] ->
        reauthorize(config, request, reason)

      {:error, {:account_mismatch, _login} = reason} ->
        reauthorize(config, request, reason)

      {:error, reason} ->
        {:error, authentication_error(reason, user)}
    end
  end

  defp reauthorize(%Config{bot_user: user} = config, request, reason) do
    IO.puts(authentication_error(reason, user))
    store = TokenStore.default()
    :ok = store.delete()
    authorize_and_validate(config, request)
  end

  defp authorize_and_validate(%Config{bot_user: user} = config, request) do
    with {:ok, password} <- maybe_auto_bootstrap(config) do
      case TokenValidator.validate(password, user, request) do
        :ok -> {:ok, password}
        {:error, reason} -> {:error, authentication_error(reason, user) <> " Restart the bot to try again."}
      end
    end
  end

  defp authentication_error(:invalid_token, _user), do: "Twitch authorization has expired or was revoked."

  defp authentication_error({:account_mismatch, login}, user),
    do: "Twitch is authorized as #{login}, but the bot username is #{user}."

  defp authentication_error(:missing_chat_scopes, _user),
    do: "Twitch authorization is missing permission to read and send chat messages."

  defp authentication_error(_reason, _user),
    do: "Could not verify Twitch authorization. Check your connection and try again."

  defp maybe_auto_bootstrap(%Config{bot_user: user}) do
    case auto_bootstrap_allowed?() do
      true ->
        IO.puts("""
        ======================================================
         Twitch Authorization Required
        ======================================================
         Opening browser to authorize with Twitch...
         Log in as #{user} and approve access.
        """)

        case OAuthBootstrap.bootstrap!() do
          :ok ->
            IO.puts("Twitch authorization received. Verifying credentials...\n")
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
        System.get_env("TF_DISABLE_AUTO_AUTH") not in ["1", "true", "TRUE"]
    end
  end

  defp test_env? do
    Code.ensure_loaded?(Mix) and function_exported?(Mix, :env, 0) and Mix.env() == :test
  end

  defp ensure_oauth_prefix("oauth:" <> _rest = value), do: value
  defp ensure_oauth_prefix(value) when is_binary(value), do: "oauth:" <> value
end
