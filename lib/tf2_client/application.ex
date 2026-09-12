defmodule TF2Client.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application
  require Logger

  alias TF2Client.Config
  alias TF2Client.SetupWizard

  @impl true
  def start(_type, _args) do
    case TF2Client.CLI.command() do
      :run ->
        maybe_run_setup_wizard()
        start_supervisor()

      :setup ->
        start_setup_command()

      :config_show ->
        start_config_show_command()

      :oauth_bootstrap ->
        start_oauth_bootstrap_command()
    end
  end

  defp maybe_run_setup_wizard do
    case Config.load() do
      {:ok, %Config{} = config} ->
        case Config.configured?(config) do
          true ->
            :ok

          false ->
            case SetupWizard.interactive?() do
              true ->
                case SetupWizard.run(config) do
                  {:ok, _updated} -> :ok
                  {:error, _reason} -> :ok
                end

              false ->
                :ok
            end
        end

      _other ->
        :ok
    end
  end

  defp start_setup_command do
    pid =
      spawn_link(fn ->
        case SetupWizard.run() do
          {:ok, _config} -> System.halt(0)
          {:error, _reason} -> System.halt(1)
        end
      end)

    {:ok, pid}
  end

  defp start_config_show_command do
    pid =
      spawn_link(fn ->
        IO.puts(Config.summary())
        System.halt(0)
      end)

    {:ok, pid}
  end

  defp start_supervisor do
    opts = [strategy: :one_for_one, name: TF2Client.Supervisor]

    with {:ok, supervisor} <- Supervisor.start_link([TF2Client.FinchConfig.child_spec()], opts) do
      start_runtime_children(supervisor)
      {:ok, supervisor}
    end
  end

  defp start_oauth_bootstrap_command do
    pid = spawn_link(&run_oauth_bootstrap_command/0)
    {:ok, pid}
  end

  defp run_oauth_bootstrap_command do
    case TF2Client.Twitch.OAuthBootstrap.bootstrap!() do
      :ok ->
        IO.puts("Authorization complete")
        System.halt(0)

      :already_authorized ->
        IO.puts("Authorization already present")
        System.halt(0)
    end
  rescue
    exception ->
      IO.puts(:stderr, "Authorization failed: #{Exception.message(exception)}")
      System.halt(1)
  end

  def start_runtime_children(supervisor \\ TF2Client.Supervisor) do
    start_child(supervisor, TF2Client.ChatbotState)

    case TF2Client.TwitchConfig.load() do
      {:ok, bot_config} ->
        start_child(supervisor, {TF2Client.TwitchSupervisor, bot_config})
        start_child(supervisor, TF2Client.RequestQueue)
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
