defmodule TF2Client.CLI do
  @moduledoc false

  def command do
    case Burrito.Util.Args.argv() do
      ["setup" | _rest] -> :setup
      ["config" | _rest] -> :config_show
      ["oauth.bootstrap" | _rest] -> :oauth_bootstrap
      ["oauth", "bootstrap" | _rest] -> :oauth_bootstrap
      _other -> :run
    end
  end
end
