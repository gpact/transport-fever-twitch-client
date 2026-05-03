defmodule TF2Client.TwitchConnectionServer do
  @moduledoc false

  use GenServer

  require Logger

  alias TMI.ChannelServer
  alias TMI.Client
  alias TMI.Conn

  @tmi_capabilities [~c"membership", ~c"tags", ~c"commands"]
  @hibernate_after_ms 20_000

  @spec start_link({module(), Conn.t()}) :: GenServer.on_start()
  def start_link({bot, conn}) do
    GenServer.start_link(__MODULE__, {bot, conn},
      name: module_name(bot),
      hibernate_after: @hibernate_after_ms
    )
  end

  @spec module_name(module()) :: module()
  def module_name(bot), do: Module.concat([bot, "ConnectionServer"])

  @impl GenServer
  def init({bot, conn}) do
    Client.add_handler(conn, self())
    {:ok, %{bot: bot, conn: conn}, {:continue, :connect}}
  end

  @impl GenServer
  def handle_continue(:connect, state) do
    connect(state.conn)
    {:noreply, state}
  end

  @impl GenServer
  def handle_info(:connect, state) do
    unless Client.is_connected?(state.conn.client) do
      connect(state.conn)
    end

    {:noreply, state}
  end

  def handle_info({:connected, _server, _port}, %{conn: conn} = state) do
    case Client.logon(conn) do
      :ok ->
        Logger.info("[TMI.ConnectionServer] LOGGED IN as #{conn.user}")

      {:error, :not_connected} ->
        Logger.error("[TMI.ConnectionServer] Cannot LOG IN, not connected")
    end

    {:noreply, state}
  end

  def handle_info(:logged_in, %{conn: conn} = state) do
    Logger.debug("[TMI] Logged in to #{conn.server}:#{conn.port}")
    Enum.each(conn.caps, &request_capabilities(conn, &1))
    Enum.each(conn.channels, &join_channel(state.bot, &1))
    {:noreply, state}
  end

  def handle_info(:disconnected, %{conn: conn} = state) do
    Logger.info("[TMI.ConnectionServer] Disconnected from #{conn.server}:#{conn.port}")
    {:stop, :normal, state}
  end

  def handle_info({:disconnected, "@" <> _cmd, _msg}, %{conn: conn} = state) do
    Logger.info("[TMI.ConnectionServer] Disconnected from #{conn.server}:#{conn.port}")
    {:noreply, state}
  end

  def handle_info({:notice, msg, _sender}, state) do
    Logger.error("[TMI.ConnectionServer] NOTICE: #{msg}")
    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  @impl GenServer
  def terminate(_, %{conn: conn}) do
    Logger.warning("[TMI.ConnectionServer] Terminating...")
    Client.quit(conn, "[TMI.ConnectionServer] Goodbye, cruel world.")
    safe_stop(conn)
  end

  defp safe_stop(%Conn{} = conn) do
    _ = safe_call(fn -> ExIRC.Client.stop!(conn.client) end)
    :ok
  end

  defp safe_call(fun) do
    try do
      fun.()
    catch
      :exit, _ -> :ok
    end
  end

  defp connect(%Conn{} = conn) do
    options = TF2Client.TwitchSSLConfig.options(conn.server)

    case ExIRC.Client.connect_ssl!(conn.client, conn.server, conn.port, options) do
      :ok ->
        Logger.info("[TMI.ConnectionServer] Connected to #{conn.server}:#{conn.port}...")
        :ok

      {:error, reason} ->
        Logger.error("[TMI.ConnectionServer] Unable to connect: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp request_capabilities(conn, cap) when cap in @tmi_capabilities do
    Logger.info("[TMI.ConnectionServer] Requesting #{cap} capability...")
    Client.command(conn, [~c"CAP REQ :twitch.tv/", cap])
  end

  defp request_capabilities(conn, cap) do
    Logger.warning("[TMI.ConnectionServer] Requesting NON-TMI capability: #{cap}...")
    Client.command(conn, to_charlist(cap))
  end

  defp join_channel(bot, channel) do
    Logger.debug("[TMI.ConnectionServer] Joining channel #{channel}...")
    ChannelServer.join(bot, channel)
  end
end
