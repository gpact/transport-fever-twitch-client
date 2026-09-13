defmodule TF2Client.Web.Router do
  @moduledoc false

  use Plug.Router
  alias Plug.Conn
  alias TF2Client.Twitch.OAuthBootstrap
  alias TF2Client.Web.Server
  alias TF2Client.Web.Status

  @dashboard_path Path.expand("../../../priv/static/dashboard/index.html", __DIR__)
  @external_resource @dashboard_path
  @dashboard_html File.read!(@dashboard_path)

  @oauth_path Path.expand("../../../priv/static/oauth/index.html", __DIR__)
  @external_resource @oauth_path
  @oauth_html File.read!(@oauth_path)

  plug(:match)
  plug(:dispatch)

  get "/" do
    conn
    |> Conn.put_resp_header("content-type", "text/html; charset=utf-8")
    |> Conn.send_resp(200, @dashboard_html)
  end

  get "/api/status" do
    conn = Conn.fetch_query_params(conn)
    channel = Map.get(conn.params, "channel")
    payload = Status.current_status(channel)
    send_json(conn, 200, payload)
  end

  post "/api/bot/toggle" do
    conn = Conn.fetch_query_params(conn)
    channel = Map.get(conn.params, "channel")
    {:ok, _enabled} = Status.toggle_bot(channel)
    send_json(conn, 200, Status.current_status(channel))
  end

  post "/api/bot/enable" do
    conn = Conn.fetch_query_params(conn)
    channel = Map.get(conn.params, "channel")
    {:ok, _enabled} = Status.enable_bot(channel)
    send_json(conn, 200, Status.current_status(channel))
  end

  post "/api/bot/disable" do
    conn = Conn.fetch_query_params(conn)
    channel = Map.get(conn.params, "channel")
    {:ok, _enabled} = Status.disable_bot(channel)
    send_json(conn, 200, Status.current_status(channel))
  end

  post "/api/purchases/toggle" do
    conn = Conn.fetch_query_params(conn)
    channel = Map.get(conn.params, "channel")
    {:ok, _paused} = Status.toggle_purchases(channel)
    send_json(conn, 200, Status.current_status(channel))
  end

  post "/api/purchases/pause" do
    conn = Conn.fetch_query_params(conn)
    channel = Map.get(conn.params, "channel")
    {:ok, _paused} = Status.pause_purchases(channel)
    send_json(conn, 200, Status.current_status(channel))
  end

  post "/api/purchases/resume" do
    conn = Conn.fetch_query_params(conn)
    channel = Map.get(conn.params, "channel")
    {:ok, _paused} = Status.resume_purchases(channel)
    send_json(conn, 200, Status.current_status(channel))
  end

  get "/api/oauth/url" do
    url = OAuthBootstrap.authorization_url()
    send_json(conn, 200, %{url: url})
  end

  post "/api/oauth/reauth" do
    url = OAuthBootstrap.authorization_url()
    _ = OAuthBootstrap.open_browser(url)
    send_json(conn, 200, %{status: "ok", url: url})
  end

  options "/oauth/token" do
    conn
    |> Conn.put_resp_header("access-control-allow-origin", "*")
    |> Conn.put_resp_header("access-control-allow-methods", "POST, OPTIONS")
    |> Conn.put_resp_header("access-control-allow-headers", "content-type")
    |> Conn.send_resp(204, "")
  end

  post "/oauth/token" do
    {:ok, body, conn} = Conn.read_body(conn)

    case Jason.decode(body) do
      {:ok, %{"access_token" => token} = payload} when is_binary(token) and byte_size(token) > 0 ->
        expires_in = parse_expires_in(Map.get(payload, "expires_in"))

        result =
          Server.deliver_token(%{
            access_token: token,
            expires_in: expires_in
          })

        conn
        |> Conn.put_resp_header("access-control-allow-origin", "*")
        |> Conn.put_resp_header("content-type", "application/json")
        |> send_json_reply(result)

      _ ->
        conn
        |> Conn.put_resp_header("access-control-allow-origin", "*")
        |> Conn.put_resp_header("content-type", "application/json")
        |> Conn.send_resp(400, Jason.encode!(%{error: "Missing access_token"}))
    end
  end

  get "/oauth/callback" do
    conn = Conn.fetch_query_params(conn)

    cond do
      is_binary(Map.get(conn.params, "code")) and byte_size(Map.get(conn.params, "code")) > 0 ->
        reply(conn, Server.deliver_code(conn.params["code"]))

      is_binary(Map.get(conn.params, "access_token")) and byte_size(Map.get(conn.params, "access_token")) > 0 ->
        expires_in = parse_expires_in(Map.get(conn.params, "expires_in"))

        reply(
          conn,
          Server.deliver_token(%{
            access_token: conn.params["access_token"],
            expires_in: expires_in
          })
        )

      true ->
        conn
        |> Conn.put_resp_header("content-type", "text/html; charset=utf-8")
        |> Conn.send_resp(200, @oauth_html)
    end
  end

  match _ do
    Conn.send_resp(conn, 404, "Not found.")
  end

  defp send_json(conn, status_code, data) do
    conn
    |> Conn.put_resp_header("content-type", "application/json")
    |> Conn.send_resp(status_code, Jason.encode!(data))
  end

  defp reply(conn, :ok) do
    Conn.send_resp(conn, 200, "Authorization complete. You may close this tab.")
  end

  defp reply(conn, {:error, :already_received}) do
    Conn.send_resp(conn, 200, "Authorization complete. You may close this tab.")
  end

  defp reply(conn, {:error, :invalid_token}) do
    Conn.send_resp(conn, 400, "Invalid authorization token.")
  end

  defp reply(conn, {:error, :invalid_code}) do
    Conn.send_resp(conn, 400, "Invalid authorization code.")
  end

  defp reply(conn, {:error, :not_running}) do
    Conn.send_resp(conn, 500, "Authorization server not running.")
  end

  defp send_json_reply(conn, :ok) do
    Conn.send_resp(conn, 200, Jason.encode!(%{status: "ok"}))
  end

  defp send_json_reply(conn, {:error, :already_received}) do
    Conn.send_resp(conn, 200, Jason.encode!(%{status: "already_received"}))
  end

  defp send_json_reply(conn, {:error, reason}) do
    Conn.send_resp(conn, 400, Jason.encode!(%{error: to_string(reason)}))
  end

  defp parse_expires_in(val) when is_integer(val), do: val

  defp parse_expires_in(val) when is_binary(val) do
    case Integer.parse(val) do
      {num, ""} -> num
      _ -> nil
    end
  end

  defp parse_expires_in(_), do: nil
end
