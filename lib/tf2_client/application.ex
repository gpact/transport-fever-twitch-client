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
        init_transport_fever_version(config.transport_fever_version)

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

  defp init_transport_fever_version(version) do
    case Application.get_env(:tf2_client, :transport_fever_version) do
      nil -> Application.put_env(:tf2_client, :transport_fever_version, version)
      _already_set -> :ok
    end
  end

  defp start_setup_command do
    pid = spawn_link(&run_setup_command/0)
    {:ok, pid}
  end

  @dialyzer {:nowarn_function, run_setup_command: 0}
  defp run_setup_command do
    case SetupWizard.run() do
      {:ok, _config} -> System.halt(0)
      {:error, _reason} -> System.halt(1)
    end
  end

  defp start_config_show_command do
    pid = spawn_link(&run_config_show_command/0)
    {:ok, pid}
  end

  @dialyzer {:nowarn_function, run_config_show_command: 0}
  defp run_config_show_command do
    IO.puts(Config.summary())
    System.halt(0)
  end

  defp start_supervisor do
    version = TF2Client.TransportFever.version()
    Logger.info("Transport Fever compatibility mode: #{version}")

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

  @dialyzer {:nowarn_function, run_oauth_bootstrap_command: 0}
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
    case start_web_server?() do
      true -> start_child(supervisor, TF2Client.Web.Server)
      false -> :ok
    end

    start_child(supervisor, TF2Client.ChatbotState)
    ensure_twitch_started(supervisor)
  end

  def ensure_twitch_started(supervisor \\ TF2Client.Supervisor) do
    case supervisor_alive?(supervisor) do
      true ->
        case Process.whereis(TF2Client.TwitchSupervisor) do
          nil ->
            start_twitch_stack(supervisor)

          _twitch_pid ->
            :ok
        end

      false ->
        :ok
    end
  end

  defp supervisor_alive?(pid) when is_pid(pid), do: Process.alive?(pid)

  defp supervisor_alive?(name) when is_atom(name) do
    case Process.whereis(name) do
      nil -> false
      pid -> Process.alive?(pid)
    end
  end

  defp supervisor_alive?(_), do: false

  defp start_twitch_stack(supervisor) do
    case TF2Client.TwitchConfig.load() do
      {:ok, bot_config} ->
        start_child(supervisor, {TF2Client.TwitchSupervisor, bot_config})
        start_child(supervisor, TF2Client.RequestQueue)
        start_child(supervisor, TF2Client.RequestTracker)
        start_child(supervisor, TF2Client.ResponsePoller)
        :ok

      {:error, reason} ->
        case log_bot_disabled?() do
          true -> Logger.warning("Twitch bot disabled: #{reason}")
          false -> :ok
        end

        {:error, reason}
    end
  end

  defp start_web_server? do
    case test_env?() do
      true ->
        System.get_env("TF_ENABLE_TEST_WEB_SERVER") in ["1", "true"]

      false ->
        System.get_env("TF_DISABLE_WEB_SERVER") not in ["1", "true"]
    end
  end

  defp test_env? do
    case Code.ensure_loaded?(Mix) and function_exported?(Mix, :env, 0) do
      true -> Mix.env() == :test
      false -> false
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
