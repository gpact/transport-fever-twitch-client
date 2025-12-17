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
    if valid_code?(code) do
      {:reply, {:error, :already_received}, state}
    else
      {:reply, {:error, :invalid_code}, state}
    end
  end

  def handle_call({:deliver_code, code}, _from, %{caller: caller, received?: false} = state) do
    if valid_code?(code) do
      send(caller, {:twitch_oauth_code, code})
      Plug.Cowboy.shutdown(@ref)
      {:stop, :normal, :ok, %{state | received?: true}}
    else
      {:reply, {:error, :invalid_code}, state}
    end
  end

  defp valid_code?(code) when is_binary(code) do
    String.trim(code) != ""
  end

  defmodule Router do
    @moduledoc false

    use Plug.Router

    alias Plug.Conn

    plug(:match)
    plug(:dispatch)

    get "/oauth/callback" do
      conn = Conn.fetch_query_params(conn)

      case Map.get(conn.params, "code") do
        code when is_binary(code) and byte_size(code) > 0 ->
          reply(conn, TF2Client.Twitch.OAuthCallbackServer.deliver_code(code))

        _ ->
          Conn.send_resp(conn, 400, "Missing authorization code.")
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

    defp reply(conn, {:error, :invalid_code}) do
      Conn.send_resp(conn, 400, "Invalid authorization code.")
    end

    defp reply(conn, {:error, :not_running}) do
      Conn.send_resp(conn, 500, "Authorization server not running.")
    end
  end
end
