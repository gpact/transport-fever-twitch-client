defmodule TF2Client.Web.Status do
  @moduledoc false

  alias TF2Client.ChatbotState
  alias TF2Client.Commands
  alias TF2Client.Config
  alias TF2Client.GameBridge

  @game_stale_threshold_seconds 30

  def current_status(target_channel \\ nil) do
    config = resolve_config()
    channel = resolve_channel(target_channel, config)

    %{
      bot_user: config.bot_user,
      channel: channel,
      twitch: twitch_status(),
      bot: bot_status(channel),
      purchases: purchases_status(channel),
      game: game_status()
    }
  end

  def twitch_status do
    bot = TF2Client.Bot
    channel_server = TMI.ChannelServer.module_name(bot)

    case Process.whereis(channel_server) do
      nil ->
        %{
          connected: false,
          channels: [],
          status: "disconnected"
        }

      pid when is_pid(pid) ->
        fetch_joined_channels(bot)
    end
  end

  defp fetch_joined_channels(bot) do
    try do
      channels = TMI.ChannelServer.list_channels(bot)
      channel_list = Enum.to_list(channels)

      case channel_list do
        [] ->
          %{
            connected: false,
            channels: [],
            status: "connecting"
          }

        joined ->
          %{
            connected: true,
            channels: joined,
            status: "connected"
          }
      end
    catch
      :exit, _ ->
        %{
          connected: false,
          channels: [],
          status: "disconnected"
        }
    end
  end

  def bot_status(nil) do
    %{
      enabled: false,
      status: "standby"
    }
  end

  def bot_status(channel) when is_binary(channel) do
    case ChatbotState.enabled?(channel) do
      true ->
        %{
          enabled: true,
          status: "active"
        }

      false ->
        %{
          enabled: false,
          status: "standby"
        }
    end
  end

  def purchases_status(nil) do
    %{
      paused: false,
      paused_commands: [],
      status: "allowed"
    }
  end

  def purchases_status(channel) when is_binary(channel) do
    paused_atoms = ChatbotState.paused_commands(channel)
    paused_strings = Enum.map(paused_atoms, &Atom.to_string/1)

    case purchases_paused?(channel) do
      true ->
        %{
          paused: true,
          paused_commands: paused_strings,
          status: "paused"
        }

      false ->
        %{
          paused: false,
          paused_commands: paused_strings,
          status: "allowed"
        }
    end
  end

  def purchases_paused?(channel) when is_binary(channel) do
    paused = ChatbotState.paused_commands(channel)
    pausable = Commands.pausable_commands()
    Enum.all?(pausable, fn cmd -> cmd in paused end)
  end

  def game_status do
    path = GameBridge.game_state_path()

    with {:ok, %File.Stat{mtime: mtime_sec}} <- File.stat(path, time: :posix),
         {:ok, save_uuid} <- GameBridge.read_save_uuid() do
      age_seconds = max(0, System.os_time(:second) - mtime_sec)

      %{
        connected: true,
        status: game_freshness(age_seconds),
        game_state_path: path,
        save_uuid: save_uuid,
        last_updated_seconds_ago: age_seconds,
        error_code: nil,
        error_message: nil
      }
    else
      {:error, reason} -> game_error(path, reason)
    end
  end

  defp game_freshness(age_seconds) when age_seconds > @game_stale_threshold_seconds, do: "stale"
  defp game_freshness(_age_seconds), do: "connected"

  defp game_error(path, {:file_error, reason}), do: game_error(path, reason)
  defp game_error(path, :game_state_missing), do: game_error(path, :enoent)

  defp game_error(path, reason) do
    {status, message} = game_error_details(reason)

    %{
      connected: false,
      status: status,
      game_state_path: path,
      save_uuid: nil,
      last_updated_seconds_ago: nil,
      error_code: Atom.to_string(reason),
      error_message: message
    }
  end

  defp game_error_details(:enoent) do
    {"waiting_for_game",
     "gameState.json was not found. Load a save with the mod enabled and check the exact filename and configured folder."}
  end

  defp game_error_details(:game_state_invalid) do
    {"invalid_game_state", "gameState.json must contain a valid JSON object. Wait for the mod to update it."}
  end

  defp game_error_details(:save_uuid_missing) do
    {"invalid_game_state", "gameState.json is missing a non-empty save_uuid. Load a save with the mod enabled."}
  end

  defp game_error_details(reason) do
    {"file_error", "Cannot access gameState.json: #{:file.format_error(reason)}."}
  end

  def toggle_bot(channel \\ nil) do
    resolved_channel = resolve_channel_for_action(channel)

    case ChatbotState.enabled?(resolved_channel) do
      true ->
        :ok = ChatbotState.disable(resolved_channel)
        {:ok, false}

      false ->
        :ok = ChatbotState.enable(resolved_channel)
        {:ok, true}
    end
  end

  def enable_bot(channel \\ nil) do
    resolved_channel = resolve_channel_for_action(channel)
    :ok = ChatbotState.enable(resolved_channel)
    {:ok, true}
  end

  def disable_bot(channel \\ nil) do
    resolved_channel = resolve_channel_for_action(channel)
    :ok = ChatbotState.disable(resolved_channel)
    {:ok, false}
  end

  def toggle_purchases(channel \\ nil) do
    resolved_channel = resolve_channel_for_action(channel)

    case purchases_paused?(resolved_channel) do
      true ->
        resume_purchases(resolved_channel)

      false ->
        pause_purchases(resolved_channel)
    end
  end

  def pause_purchases(channel \\ nil) do
    resolved_channel = resolve_channel_for_action(channel)

    Enum.each(Commands.pausable_commands(), fn command ->
      :ok = ChatbotState.pause(resolved_channel, command)
    end)

    {:ok, true}
  end

  def resume_purchases(channel \\ nil) do
    resolved_channel = resolve_channel_for_action(channel)

    Enum.each(Commands.pausable_commands(), fn command ->
      :ok = ChatbotState.resume(resolved_channel, command)
    end)

    {:ok, false}
  end

  defp resolve_channel_for_action(channel) when is_binary(channel) and channel != "" do
    normalize_channel(channel)
  end

  defp resolve_channel_for_action(_) do
    config = resolve_config()

    case config.channels do
      [first | _] -> normalize_channel(first)
      _ -> "default"
    end
  end

  defp resolve_channel(channel, _config) when is_binary(channel) and channel != "" do
    normalize_channel(channel)
  end

  defp resolve_channel(_target, config) do
    case config.channels do
      [first | _] -> normalize_channel(first)
      _ -> nil
    end
  end

  defp resolve_config do
    case Config.load() do
      {:ok, %Config{} = config} -> config
      _ -> %Config{}
    end
  end

  defp normalize_channel(channel) when is_binary(channel) do
    channel
    |> String.trim()
    |> String.downcase()
    |> String.trim_leading("#")
  end
end
