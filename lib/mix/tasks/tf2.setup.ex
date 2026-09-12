defmodule Mix.Tasks.Tf2.Setup do
  @shortdoc "Interactive configuration wizard for TF2Client"
  @moduledoc "Guides you through configuring your Twitch channel, credentials, and settings."

  use Mix.Task

  alias TF2Client.SetupWizard

  @impl Mix.Task
  def run(_args) do
    case SetupWizard.run() do
      {:ok, _config} ->
        Mix.shell().info("Setup complete! You can now start the bot with: mix run --no-halt (or iex -S mix)")

      {:error, reason} ->
        Mix.shell().error("Setup was not completed: #{inspect(reason)}")
    end
  end
end
