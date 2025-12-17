defmodule Mix.Tasks.Twitch.Oauth.Bootstrap do
  @moduledoc "Runs the one-time Twitch OAuth bootstrap flow."

  use Mix.Task

  @shortdoc "Run Twitch OAuth bootstrap"

  @impl Mix.Task
  def run(_args) do
    case TF2Client.Twitch.OAuthBootstrap.bootstrap!() do
      :ok ->
        Mix.shell().info("Authorization complete")

      :already_authorized ->
        Mix.shell().info("Authorization already present")
    end
  end
end
