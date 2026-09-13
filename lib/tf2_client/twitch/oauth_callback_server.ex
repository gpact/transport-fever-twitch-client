defmodule TF2Client.Twitch.OAuthCallbackServer do
  @moduledoc false

  alias TF2Client.Web.Server

  defdelegate start_link(opts), to: Server
  defdelegate stop, to: Server
  defdelegate running?, to: Server
  defdelegate register_caller(caller), to: Server
  defdelegate deliver_code(code), to: Server
  defdelegate deliver_token(token_data), to: Server

  defmodule Router do
    @moduledoc false

    alias TF2Client.Web.Router

    defdelegate init(opts), to: Router
    defdelegate call(conn, opts), to: Router
  end
end
