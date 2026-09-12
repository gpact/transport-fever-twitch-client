defmodule TF2Client do
  @moduledoc """
  Convenience helpers for interacting with TF2Client from IEx or scripts.
  """

  alias TF2Client.Application, as: App
  alias TF2Client.Config
  alias TF2Client.SetupWizard

  @doc """
  Runs the interactive setup wizard.
  """
  def setup do
    SetupWizard.run()
  end

  @doc """
  Starts or restarts the Twitch bot children under the supervisor.
  """
  def start_bot do
    App.start_runtime_children()
  end

  @doc """
  Inspects the current configuration.
  """
  def config do
    {:ok, config} = Config.load()
    config
  end
end
