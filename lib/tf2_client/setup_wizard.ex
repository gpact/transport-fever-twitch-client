defmodule TF2Client.SetupWizard do
  @moduledoc false

  alias TF2Client.Config

  def interactive? do
    case non_interactive_env?() do
      true ->
        false

      false ->
        case :io.getopts() do
          opts when is_list(opts) ->
            Keyword.get(opts, :stdin, false) and Keyword.get(opts, :terminal, false)

          _other ->
            false
        end
    end
  end

  def run do
    {:ok, config} = Config.load()
    run(config)
  end

  def run(%Config{} = existing_config) do
    IO.puts("""
    ========================================================
        Transport Fever 2 Twitch Bot - Setup Wizard
    ========================================================
    Configure your bot settings. Press Enter to keep current values.
    """)

    with {:ok, channel} <- prompt_channel(existing_config.channels),
         default_user = existing_config.bot_user || channel,
         {:ok, bot_user} <- prompt_bot_user(default_user),
         {:ok, client_id} <-
           prompt_credential(
             "Twitch Client ID (optional, press Enter to use default)",
             existing_config.client_id
           ),
         {:ok, client_secret} <-
           prompt_credential(
             "Twitch Client Secret (optional, press Enter for browser login)",
             existing_config.client_secret
           ),
         {:ok, bot_oauth} <-
           prompt_optional(
             "Twitch Bot OAuth IRC token (optional, leave blank to use browser login)",
             existing_config.bot_oauth
           ) do
      updated_config = %Config{
        existing_config
        | channels: [channel],
          bot_user: bot_user,
          client_id: client_id,
          client_secret: client_secret,
          bot_oauth: bot_oauth
      }

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

  defp channel_prompt_label(""), do: "Twitch channel: "
  defp channel_prompt_label(default), do: "Twitch channel [#{default}]: "

  defp prompt_bot_user(default) do
    prompt_label = "Bot username [#{default}]: "

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

  defp prompt_optional(label, current_value) do
    display_current = mask_credential(current_value)
    prompt_label = credential_prompt_label(label, display_current)

    case read_input(prompt_label) do
      {:ok, ""} -> {:ok, current_value}
      {:ok, input} -> {:ok, input}
      {:error, reason} -> {:error, reason}
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
