defmodule TF2Client.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: TF2Client.Supervisor]

    with {:ok, supervisor} <- Supervisor.start_link([{Finch, name: TF2Client.Finch}], opts) do
      start_runtime_children(supervisor)
      {:ok, supervisor}
    end
  end

  defp start_runtime_children(supervisor) do
    start_child(supervisor, TF2Client.ChatbotState)

    case TF2Client.TwitchConfig.from_env() do
      {:ok, bot_config} ->
        start_child(supervisor, {TF2Client.TwitchSupervisor, bot_config})
        start_child(supervisor, TF2Client.RequestTracker)
        start_child(supervisor, TF2Client.ResponsePoller)
        :ok

      {:error, reason} ->
        if log_bot_disabled?() do
          Logger.warning("Twitch bot disabled: #{reason}")
        end

        :ok
    end
  end

  defp start_child(supervisor, child_spec) do
    case Supervisor.start_child(supervisor, child_spec) do
      {:ok, _pid} -> :ok
      {:ok, _pid, _info} -> :ok
      {:error, {:already_started, _pid}} -> :ok
      {:error, reason} -> raise "Failed to start child #{inspect(child_spec)}: #{inspect(reason)}"
    end
  end

  defp log_bot_disabled? do
    case Code.ensure_loaded?(Mix) and function_exported?(Mix, :env, 0) do
      true -> Mix.env() != :test
      false -> true
    end
  end
end
