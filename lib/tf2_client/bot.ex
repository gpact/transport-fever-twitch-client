defmodule TF2Client.Bot do
  @moduledoc false

  use TMI

  alias TF2Client.Commands
  alias TF2Client.ChatbotState
  alias TF2Client.Requests

  @impl TMI.Handler
  def handle_message(message, sender, chat) do
    handle_message(message, sender, chat, %{})
  end

  @impl TMI.Handler
  def handle_message(message, sender, chat, tags) do
    case Commands.parse(message) do
      :ignore ->
        :ok

      {:ok, {:tf2_on}} ->
        maybe_toggle(chat, sender, tags, :enable)

      {:ok, {:tf2_off}} ->
        maybe_toggle(chat, sender, tags, :disable)

      {:ok, command} ->
        if ChatbotState.enabled?(chat) do
          case Requests.handle_chat_command(command, sender, chat) do
            :ignore -> :ok
            {:reply, reply} when is_binary(reply) -> say(chat, reply)
          end
        else
          :ok
        end

      {:error, error} when is_binary(error) ->
        if ChatbotState.enabled?(chat) do
          say(chat, "@#{sender} #{error}")
        else
          :ok
        end
    end
  end

  defp maybe_toggle(chat, sender, tags, :enable) do
    if broadcaster_or_mod?(sender, chat, tags) do
      :ok = ChatbotState.enable(chat)
      say(chat, "TF2 bot enabled.")
    else
      :ok
    end
  end

  defp maybe_toggle(chat, sender, tags, :disable) do
    if broadcaster_or_mod?(sender, chat, tags) do
      :ok = ChatbotState.disable(chat)
      say(chat, "TF2 bot disabled.")
    else
      :ok
    end
  end

  defp broadcaster_or_mod?(sender, chat, tags) when is_binary(sender) and is_binary(chat) and is_map(tags) do
    mod = truthy_tag?(tags, "mod") or truthy_tag?(tags, :mod)
    broadcaster = broadcaster_badge?(tags) or sender_is_channel_owner?(sender, chat)
    mod or broadcaster
  end

  defp truthy_tag?(tags, key) do
    case Map.get(tags, key) do
      true -> true
      1 -> true
      "1" -> true
      "true" -> true
      "TRUE" -> true
      _ -> false
    end
  end

  defp broadcaster_badge?(tags) do
    badges =
      case Map.get(tags, "badges") do
        value when is_binary(value) -> value
        _ -> Map.get(tags, :badges)
      end

    case badges do
      value when is_binary(value) -> String.contains?(value, "broadcaster/")
      _ -> false
    end
  end

  defp sender_is_channel_owner?(sender, chat) do
    sender = normalize_channel(sender)
    chat = normalize_channel(chat)
    sender != "" and sender == chat
  end

  defp normalize_channel(value) when is_binary(value) do
    value =
      value
      |> String.trim()
      |> String.downcase()

    String.trim_leading(value, "#")
  end
end
