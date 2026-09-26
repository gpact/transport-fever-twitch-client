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

      {:ok, {:tf_on}} ->
        maybe_toggle(chat, sender, tags, :enable)

      {:ok, {:tf_off}} ->
        maybe_toggle(chat, sender, tags, :disable)

      {:ok, {:paused}} ->
        maybe_show_paused(chat, sender, tags)

      {:ok, {:pause, target}} ->
        maybe_pause(chat, sender, tags, target)

      {:ok, {:resume, target}} ->
        maybe_resume(chat, sender, tags, target)

      {:ok, command} ->
        maybe_handle_command(chat, sender, command, tags)

      {:error, error} when is_binary(error) ->
        maybe_report_error(chat, sender, message, error)
    end
  end

  defp maybe_toggle(chat, sender, tags, :enable) do
    case broadcaster_or_mod?(sender, chat, tags) do
      true ->
        :ok = ChatbotState.enable(chat)
        say(chat, "Transport Fever bot enabled.")

      false ->
        :ok
    end
  end

  defp maybe_toggle(chat, sender, tags, :disable) do
    case broadcaster_or_mod?(sender, chat, tags) do
      true ->
        :ok = ChatbotState.disable(chat)
        say(chat, "Transport Fever bot disabled.")

      false ->
        :ok
    end
  end

  defp maybe_pause(chat, sender, tags, target) when is_atom(target) do
    case target do
      :all -> maybe_pause_all(chat, sender, tags)
      _ -> maybe_pause_one(chat, sender, tags, target)
    end
  end

  defp maybe_resume(chat, sender, tags, target) when is_atom(target) do
    case target do
      :all -> maybe_resume_all(chat, sender, tags)
      _ -> maybe_resume_one(chat, sender, tags, target)
    end
  end

  defp maybe_pause_all(chat, sender, tags) do
    case broadcaster_or_mod?(sender, chat, tags) do
      true ->
        pause_all(chat)
        say(chat, "Paused all redemptions.")

      false ->
        :ok
    end
  end

  defp maybe_pause_one(chat, sender, tags, target) do
    case broadcaster_or_mod?(sender, chat, tags) do
      true ->
        :ok = ChatbotState.pause(chat, target)
        say(chat, "Paused #{pause_label(target)}.")

      false ->
        :ok
    end
  end

  defp maybe_resume_all(chat, sender, tags) do
    case broadcaster_or_mod?(sender, chat, tags) do
      true ->
        resume_all(chat)
        say(chat, "Resumed all redemptions.")

      false ->
        :ok
    end
  end

  defp maybe_resume_one(chat, sender, tags, target) do
    case broadcaster_or_mod?(sender, chat, tags) do
      true ->
        :ok = ChatbotState.resume(chat, target)
        say(chat, "Resumed #{pause_label(target)}.")

      false ->
        :ok
    end
  end

  defp maybe_handle_command(chat, sender, command, tags) do
    case ChatbotState.enabled?(chat) do
      true ->
        case paused_command?(chat, command) do
          true ->
            :ok

          false ->
            case Requests.handle_chat_command(command, sender, chat, tags) do
              :ignore -> :ok
              {:reply, reply} when is_binary(reply) -> say(chat, reply)
            end
        end

      false ->
        :ok
    end
  end

  defp maybe_show_paused(chat, sender, tags) do
    case ChatbotState.enabled?(chat) do
      true ->
        maybe_send_paused_list(chat, sender, tags)

      false ->
        :ok
    end
  end

  defp maybe_send_paused_list(chat, sender, tags) do
    case broadcaster_or_mod?(sender, chat, tags) do
      true ->
        paused = ChatbotState.paused_commands(chat)
        say(chat, paused_list_message(paused))

      false ->
        :ok
    end
  end

  defp maybe_report_error(chat, sender, message, error) do
    case ChatbotState.enabled?(chat) do
      true ->
        case paused_message_command?(chat, message) do
          true -> :ok
          false -> say(chat, "@#{sender} #{error}")
        end

      false ->
        :ok
    end
  end

  defp broadcaster_or_mod?(sender, chat, tags) when is_binary(sender) and is_binary(chat) and is_map(tags) do
    Map.get(tags, "mod") == "1" or broadcaster_badge?(tags) or sender_is_channel_owner?(sender, chat)
  end

  defp broadcaster_badge?(tags) do
    with badges when is_binary(badges) <- Map.get(tags, "badges") do
      String.contains?(badges, "broadcaster/")
    else
      _ -> false
    end
  end

  defp paused_command?(chat, command) do
    case Commands.pausable_command_key(command) do
      nil -> false
      target -> ChatbotState.paused?(chat, target)
    end
  end

  defp paused_message_command?(chat, message) do
    case Commands.command_name(message) do
      nil ->
        false

      command_name ->
        case Commands.pausable_command_name(command_name) do
          nil -> false
          target -> ChatbotState.paused?(chat, target)
        end
    end
  end

  defp pause_label(:claim), do: "company claims"
  defp pause_label(:town), do: "town purchases"
  defp pause_label(:town_rename), do: "town renames"
  defp pause_label(:line), do: "line purchases"
  defp pause_label(:vehicle), do: "vehicle purchases"
  defp pause_label(other), do: Atom.to_string(other)

  defp paused_list_message([]), do: "No redemptions are paused."

  defp paused_list_message(paused) when is_list(paused) do
    labels = Enum.map(paused, &pause_label/1)
    "Paused redemptions: " <> Enum.join(labels, ", ")
  end

  defp pause_all(chat) do
    Enum.each(Commands.pausable_commands(), fn command ->
      :ok = ChatbotState.pause(chat, command)
    end)
  end

  defp resume_all(chat) do
    Enum.each(Commands.pausable_commands(), fn command ->
      :ok = ChatbotState.resume(chat, command)
    end)
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
