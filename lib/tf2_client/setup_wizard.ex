defmodule TF2Client.SetupWizard do
  @moduledoc false

  alias TF2Client.Config

  def automatic_setup? do
    not non_interactive_env?()
  end

  def ensure_configured(%Config{enable_bot: false} = config), do: {:ok, config}

  def ensure_configured(%Config{} = config) do
    case Config.configured?(config) do
      true -> {:ok, config}
      false -> run(config)
    end
  end

  def run do
    with {:ok, config} <- Config.load() do
      run(config)
    end
  end

  def run(%Config{} = existing_config) do
    IO.puts("""
    ========================================================
        Transport Fever Twitch Bot - Setup Wizard
    ========================================================
    Connect the bot to your Twitch channel.

    1. Browser authentication (recommended)
       Only your Twitch username is required. No developer credentials needed.
    2. Manual configuration (advanced)
       Use your own Twitch application or an existing OAuth IRC token.
    """)

    with {:ok, method} <- prompt_authentication_method(),
         {:ok, updated_config} <- configure(method, existing_config) do
      target_path = Config.config_path()
      :ok = Config.save(updated_config, target_path)

      IO.puts("\nConfiguration saved to: #{target_path}")
      {:ok, updated_config}
    else
      {:error, reason} ->
        IO.puts(:stderr, "Notice: setup cancelled or input unavailable (#{inspect(reason)}).")
        {:error, reason}
    end
  end

  defp prompt_authentication_method do
    case read_input("Choose authentication method [1]: ") do
      {:ok, choice} when choice in ["", "1"] ->
        {:ok, :browser}

      {:ok, "2"} ->
        {:ok, :manual}

      {:ok, _other} ->
        IO.puts("Please enter 1 for browser authentication or 2 for manual configuration.")
        prompt_authentication_method()

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp configure(:browser, %Config{} = existing_config) do
    IO.puts("""

    Browser authentication
    Enter the Twitch username of the channel where you stream.
    The bot username defaults to your saved bot account, or your streaming username.
    Press Enter to accept it, or enter a separate bot username.
    This option uses the built-in Twitch application and replaces any manual credentials.
    """)

    with {:ok, channel} <- prompt_channel(existing_config.channels),
         {:ok, bot_user} <- prompt_bot_user(existing_config.bot_user || channel) do
      IO.puts("""

      When the bot starts, your browser will open if authorization is needed.
      Log in to Twitch as #{bot_user} and approve access, then return here.
      If the browser does not open, use the authorization link shown in this window.
      """)

      {:ok,
       %Config{
         existing_config
         | channels: [channel],
           bot_user: bot_user,
           client_id: nil,
           client_secret: nil,
           bot_oauth: nil,
           redirect_uri: %Config{}.redirect_uri
       }}
    end
  end

  defp configure(:manual, %Config{} = existing_config) do
    IO.puts("""

    Manual configuration
    Press Enter to keep current values or skip optional fields.
    Client ID and Client Secret are only for your own Twitch application.
    Without an OAuth IRC token, the bot uses browser authentication when needed.
    """)

    with {:ok, channel} <- prompt_channel(existing_config.channels),
         {:ok, bot_user} <- prompt_bot_user(existing_config.bot_user || channel),
         {:ok, client_id} <-
           prompt_credential("Twitch Client ID (optional; built-in default if unset)", existing_config.client_id),
         {:ok, client_secret} <-
           prompt_credential("Twitch Client Secret (optional)", existing_config.client_secret),
         {:ok, bot_oauth} <-
           prompt_credential("Twitch Bot OAuth IRC token (optional; browser login if unset)", existing_config.bot_oauth) do
      {:ok,
       %Config{
         existing_config
         | channels: [channel],
           bot_user: bot_user,
           client_id: client_id,
           client_secret: client_secret,
           bot_oauth: bot_oauth
       }}
    end
  end

  defp prompt_channel(current_channels) do
    default = List.first(current_channels) || ""
    prompt_label = channel_prompt_label(default)

    case read_input(prompt_label) do
      {:ok, ""} when default != "" ->
        {:ok, String.downcase(default)}

      {:ok, ""} ->
        IO.puts("Channel name cannot be empty. Please enter a channel name.")
        prompt_channel(current_channels)

      {:ok, input} ->
        cleaned =
          input
          |> String.trim_leading("#")
          |> String.downcase()

        {:ok, cleaned}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp channel_prompt_label(""), do: "Your Twitch username (streaming channel): "
  defp channel_prompt_label(default), do: "Your Twitch username (streaming channel) [#{default}]: "

  defp prompt_bot_user(default) do
    prompt_label = "Bot username (optional) [#{default}]: "

    case read_input(prompt_label) do
      {:ok, ""} -> {:ok, String.downcase(default)}
      {:ok, input} -> {:ok, String.downcase(input)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp prompt_credential(label, current_value) do
    display_current = mask_credential(current_value)
    prompt_label = credential_prompt_label(label, display_current)

    case read_input(prompt_label) do
      {:ok, ""} when is_binary(current_value) and current_value != "" ->
        {:ok, current_value}

      {:ok, ""} ->
        {:ok, nil}

      {:ok, input} ->
        {:ok, input}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp credential_prompt_label(label, ""), do: "#{label}: "
  defp credential_prompt_label(label, display), do: "#{label} [#{display}]: "

  defp read_input(prompt) do
    case IO.gets(prompt) do
      line when is_binary(line) ->
        {:ok, String.trim(line)}

      :eof ->
        {:error, :eof}

      {:error, reason} ->
        {:error, reason}

      _other ->
        {:error, :unsupported}
    end
  end

  defp mask_credential(nil), do: ""
  defp mask_credential(""), do: ""

  defp mask_credential(val) when is_binary(val) do
    length = String.length(val)

    case length <= 8 do
      true ->
        "****"

      false ->
        String.slice(val, 0, 4) <> "..." <> String.slice(val, -4, 4)
    end
  end

  defp non_interactive_env? do
    test_env?() or iex_env?()
  end

  defp test_env? do
    Code.ensure_loaded?(Mix) and function_exported?(Mix, :env, 0) and Mix.env() == :test
  end

  defp iex_env? do
    # credo:disable-for-next-line Credo.Check.Refactor.Apply
    Code.ensure_loaded?(IEx) and function_exported?(IEx, :started?, 0) and apply(IEx, :started?, [])
  end
end
