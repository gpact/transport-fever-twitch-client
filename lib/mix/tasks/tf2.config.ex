defmodule Mix.Tasks.Tf2.Config do
  @shortdoc "Displays the current TF2Client configuration"
  @moduledoc "Displays the loaded TF2Client configuration and credential status."

  use Mix.Task

  alias TF2Client.Config

  @impl Mix.Task
  def run(_args) do
    IO.puts(Config.summary())
  end
end
