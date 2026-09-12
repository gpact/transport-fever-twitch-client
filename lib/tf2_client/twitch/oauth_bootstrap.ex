defmodule TF2Client.Twitch.OAuthBootstrap do
  @moduledoc false

  alias TF2Client.Config
  alias TF2Client.Twitch.OAuthCallbackServer
  alias TF2Client.Twitch.TokenRefresher
  alias TF2Client.Twitch.TokenStore

  @scopes "chat:read chat:edit channel:moderate"
  @authorize_url "https://id.twitch.tv/oauth2/authorize"
  @timeout_ms 300_000

  @doc false
  def browser_command_for_os(url, os_type) when is_binary(url) do
    case os_type do
      {:unix, :darwin} ->
        {"open", [url]}

      {:unix, _} ->
        {"xdg-open", [url]}

      {:win32, _} ->
        {"rundll32.exe", ["url.dll,FileProtocolHandler", url]}
    end
  end

  def bootstrap! do
    store = TokenStore.default()

    case store.load() do
      {:ok, %{refresh_token: refresh_token}} when is_binary(refresh_token) and refresh_token != "" ->
        :already_authorized

      _ ->
        do_bootstrap!(store)
    end
  end

  defp do_bootstrap!(store) do
    ensure_oauth_apps_started!()
    finch_supervisor = ensure_finch_supervised!()

    try do
      {:ok, _pid} = OAuthCallbackServer.start_link(caller: self())
      open_browser!(authorization_url())

      code = await_code!()
      tokens = TokenRefresher.exchange_code_for_tokens!(code)
      store.save(tokens)
      :ok
    after
      OAuthCallbackServer.stop()
      stop_supervisor(finch_supervisor)
    end
  end

  defp ensure_oauth_apps_started! do
    ensure_started!(:telemetry)
    ensure_started!(:plug_cowboy)
    ensure_started!(:ssl)
    ensure_started!(:castore)
    ensure_started!(:finch)
    :ok
  end

  defp ensure_started!(app) when is_atom(app) do
    case Application.ensure_all_started(app) do
      {:ok, _apps} -> :ok
      {:error, {failed_app, reason}} -> raise "Failed to start #{failed_app}: #{inspect(reason)}"
    end
  end

  defp await_code! do
    receive do
      {:twitch_oauth_code, code} when is_binary(code) and code != "" ->
        code
    after
      @timeout_ms ->
        raise "OAuth authorization timed out."
    end
  end

  defp authorization_url do
    client_id = Config.client_id()
    redirect_uri = Config.redirect_uri()

    query =
      URI.encode_query(%{
        client_id: client_id,
        redirect_uri: redirect_uri,
        response_type: "code",
        scope: @scopes
      })

    @authorize_url <> "?" <> query
  end

  defp open_browser!(url) when is_binary(url) do
    IO.puts("""
    Please open the following authorization URL in your browser if it does not open automatically:
      #{url}
    """)

    {cmd, args} = browser_command(url)

    case System.cmd(cmd, args) do
      {_output, 0} ->
        :ok

      {_output, status} ->
        IO.puts(
          :stderr,
          "Notice: could not launch browser automatically (#{cmd}, status #{status}). Please use the link above."
        )

        :ok
    end
  rescue
    e in ErlangError ->
      IO.puts(
        :stderr,
        "Notice: could not launch browser automatically (#{Exception.message(e)}). Please use the link above."
      )

      :ok
  end

  defp browser_command(url) do
    browser_command_for_os(url, :os.type())
  end

  defp ensure_finch_supervised! do
    if Process.whereis(TF2Client.Finch) do
      nil
    else
      {:ok, pid} = Supervisor.start_link([TF2Client.FinchConfig.child_spec()], strategy: :one_for_one)
      pid
    end
  end

  defp stop_supervisor(nil), do: :ok

  defp stop_supervisor(pid) when is_pid(pid) do
    Supervisor.stop(pid)
    :ok
  end
end
