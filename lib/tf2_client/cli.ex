defmodule TF2Client.CLI do
  @moduledoc false

  def command do
    case argv() do
      ["setup" | _rest] -> :setup
      ["config" | _rest] -> :config_show
      ["oauth.bootstrap" | _rest] -> :oauth_bootstrap
      ["oauth", "bootstrap" | _rest] -> :oauth_bootstrap
      _other -> :run
    end
  end

  defp argv do
    case System.get_env("__BURRITO") do
      nil -> System.argv()
      _value -> Enum.map(:init.get_plain_arguments(), &to_string/1)
    end
  end
end
