defmodule TF2Client.Bot do
  @moduledoc false

  use TMI

  alias TF2Client.Commands
  alias TF2Client.Requests

  @impl TMI.Handler
  def handle_message(message, sender, chat) do
    case Commands.parse(message) do
      :ignore ->
        :ok

      {:ok, command} ->
        case Requests.handle_chat_command(command, sender, chat) do
          :ignore -> :ok
          {:reply, reply} when is_binary(reply) -> say(chat, reply)
        end

      {:error, error} when is_binary(error) ->
        say(chat, "@#{sender} #{error}")
    end
  end
end

