defmodule TF2Client.Chat do
  @moduledoc false

  @callback send(channel :: binary(), message :: binary()) :: :ok

  def send(channel, message) when is_binary(channel) and is_binary(message) do
    sender().send(channel, message)
  end

  defp sender do
    Application.get_env(:tf2_client, :chat_sender, TF2Client.Chat.TMI)
  end
end

