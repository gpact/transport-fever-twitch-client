defmodule TF2Client.Twitch.TokenStore do
  @moduledoc false

  @type token_map :: %{
          access_token: binary(),
          refresh_token: binary(),
          expires_at: integer()
        }

  @callback load() :: {:ok, token_map()} | :error
  @callback save(token_map()) :: :ok

  def default, do: TF2Client.Twitch.FileTokenStore
end
