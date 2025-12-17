defmodule TF2Client.Chat.TMI do
  @moduledoc false

  @behaviour TF2Client.Chat

  @impl TF2Client.Chat
  def send(channel, message) do
    TF2Client.Bot.say(channel, message)
    :ok
  end
end
