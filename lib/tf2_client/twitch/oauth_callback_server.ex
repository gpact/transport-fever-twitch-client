defmodule TF2Client.Twitch.OAuthCallbackServer do
  @moduledoc false

  use GenServer

  @name __MODULE__
  @ref {__MODULE__, :http}
  @port 4000

  def start_link(opts) do
    caller = Keyword.fetch!(opts, :caller)
    GenServer.start_link(__MODULE__, %{caller: caller, received?: false}, name: @name)
  end

  def stop do
    GenServer.stop(@name, :normal)
  catch
    :exit, _ -> :ok
  end

  def deliver_code(code) when is_binary(code) do
    GenServer.call(@name, {:deliver_code, code})
  catch
    :exit, _ -> {:error, :not_running}
  end

  def deliver_token(token_data) when is_map(token_data) do
    GenServer.call(@name, {:deliver_token, token_data})
  catch
    :exit, _ -> {:error, :not_running}
  end

  @impl GenServer
  def init(%{caller: caller} = state) do
    {:ok, _pid} = Plug.Cowboy.http(__MODULE__.Router, [], port: @port, ref: @ref, ip: {127, 0, 0, 1})
    {:ok, Map.put(state, :caller, caller)}
  end

  @impl GenServer
  def terminate(_reason, _state) do
    Plug.Cowboy.shutdown(@ref)
    :ok
  end

  @impl GenServer
  def handle_call({:deliver_code, code}, _from, %{received?: true} = state) do
    case valid_string?(code) do
      true -> {:reply, {:error, :already_received}, state}
      false -> {:reply, {:error, :invalid_code}, state}
    end
  end

  def handle_call({:deliver_code, code}, _from, %{caller: caller, received?: false} = state) do
    case valid_string?(code) do
      true ->
        send(caller, {:twitch_oauth_code, code})
        Plug.Cowboy.shutdown(@ref)
        {:stop, :normal, :ok, %{state | received?: true}}

      false ->
        {:reply, {:error, :invalid_code}, state}
    end
  end

  def handle_call({:deliver_token, %{access_token: token} = _data}, _from, %{received?: true} = state) do
    case valid_string?(token) do
      true -> {:reply, {:error, :already_received}, state}
      false -> {:reply, {:error, :invalid_token}, state}
    end
  end

  def handle_call({:deliver_token, %{access_token: token} = data}, _from, %{caller: caller, received?: false} = state) do
    case valid_string?(token) do
      true ->
        send(caller, {:twitch_oauth_token, data})
        Plug.Cowboy.shutdown(@ref)
        {:stop, :normal, :ok, %{state | received?: true}}

      false ->
        {:reply, {:error, :invalid_token}, state}
    end
  end

  def handle_call({:deliver_token, _invalid}, _from, state) do
    {:reply, {:error, :invalid_token}, state}
  end

  defp valid_string?(str) when is_binary(str) do
    String.trim(str) != ""
  end

  defp valid_string?(_), do: false

  defmodule Router do
    @moduledoc false

    use Plug.Router

    alias Plug.Conn

    @html_path Path.expand("../../../priv/static/oauth/index.html", __DIR__)
    @external_resource @html_path
    @callback_html File.read!(@html_path)

    plug(:match)
    plug(:dispatch)

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
            TF2Client.Twitch.OAuthCallbackServer.deliver_token(%{
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
          reply(conn, TF2Client.Twitch.OAuthCallbackServer.deliver_code(conn.params["code"]))

        is_binary(Map.get(conn.params, "access_token")) and byte_size(Map.get(conn.params, "access_token")) > 0 ->
          expires_in = parse_expires_in(Map.get(conn.params, "expires_in"))

          reply(
            conn,
            TF2Client.Twitch.OAuthCallbackServer.deliver_token(%{
              access_token: conn.params["access_token"],
              expires_in: expires_in
            })
          )

        true ->
          conn
          |> Conn.put_resp_header("content-type", "text/html; charset=utf-8")
          |> Conn.send_resp(200, @callback_html)
      end
    end

    match _ do
      Conn.send_resp(conn, 404, "Not found.")
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
end
