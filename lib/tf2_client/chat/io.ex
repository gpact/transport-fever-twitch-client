defmodule TF2Client.Chat.IO do
  @moduledoc false

  @behaviour TF2Client.Chat

  @impl TF2Client.Chat
  def send(channel, message) do
    IO.puts("[#{channel}] #{message}")
    :ok
  end
end
