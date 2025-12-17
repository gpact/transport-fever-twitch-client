defmodule TF2Client.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    children =
      [{Finch, name: TF2Client.Finch}] ++
        case TF2Client.TwitchConfig.from_env() do
          {:ok, bot_config} ->
            [
              {TF2Client.TwitchSupervisor, bot_config},
              TF2Client.RequestTracker,
              TF2Client.ResponsePoller
            ]

          {:error, reason} ->
            if Mix.env() != :test do
              Logger.warning("Twitch bot disabled: #{reason}")
            end

            []
        end

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: TF2Client.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
