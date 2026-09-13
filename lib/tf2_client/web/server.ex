defmodule TF2Client.Web.Server do
  @moduledoc false

  use GenServer
  require Logger

  alias TF2Client.Twitch.TokenRefresher
  alias TF2Client.Twitch.TokenStore

  @name __MODULE__
  @ref {__MODULE__, :http}
  @default_port 4000
  @default_token_lifespan_seconds div(:timer.hours(60 * 24), 1000)

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 5000
    }
  end

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: @name)
  end

  def stop do
    GenServer.stop(@name, :normal)
  catch
    :exit, _ -> :ok
  end

  def running? do
    case Process.whereis(@name) do
      nil -> false
      pid -> Process.alive?(pid)
    end
  end

  def register_caller(caller) when is_pid(caller) do
    GenServer.call(@name, {:register_caller, caller})
  catch
    :exit, _ -> {:error, :not_running}
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
  def init(opts) do
    caller = Keyword.get(opts, :caller)
    port = resolve_port(opts)
    ref = Keyword.get(opts, :ref, @ref)

    case Plug.Cowboy.http(TF2Client.Web.Router, [], port: port, ref: ref, ip: {127, 0, 0, 1}) do
      {:ok, _pid} ->
        {:ok, %{caller: caller, port: port, ref: ref}}

      {:error, :eaddrinuse} ->
        {:error, :eaddrinuse}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl GenServer
  def terminate(_reason, %{ref: ref}) do
    Plug.Cowboy.shutdown(ref)
    :ok
  end

  def terminate(_reason, _state), do: :ok

  @impl GenServer
  def handle_call({:register_caller, caller}, _from, state) do
    {:reply, :ok, %{state | caller: caller}}
  end

  def handle_call({:deliver_code, code}, _from, %{caller: caller} = state) do
    case valid_string?(code) do
      true ->
        handle_code_delivery(caller, code)
        {:reply, :ok, state}

      false ->
        {:reply, {:error, :invalid_code}, state}
    end
  end

  def handle_call({:deliver_token, %{access_token: token} = data}, _from, %{caller: caller} = state) do
    case valid_string?(token) do
      true ->
        handle_token_delivery(caller, data)
        {:reply, :ok, state}

      false ->
        {:reply, {:error, :invalid_token}, state}
    end
  end

  def handle_call({:deliver_token, _invalid}, _from, state) do
    {:reply, {:error, :invalid_token}, state}
  end

  defp handle_code_delivery(caller, code) when is_pid(caller) do
    send(caller, {:twitch_oauth_code, code})
  end

  defp handle_code_delivery(_no_caller, code) do
    try do
      tokens = TokenRefresher.exchange_code_for_tokens!(code)
      store = TokenStore.default()
      store.save(tokens)
      TF2Client.Application.ensure_twitch_started()
    rescue
      e ->
        Logger.error("Failed to exchange OAuth code: #{Exception.message(e)}")
    end
  end

  defp handle_token_delivery(caller, %{access_token: token} = data) do
    expires_in = Map.get(data, :expires_in) || @default_token_lifespan_seconds
    now = System.os_time(:second)

    token_map = %{
      access_token: token,
      refresh_token: nil,
      expires_at: now + expires_in
    }

    store = TokenStore.default()
    store.save(token_map)
    TF2Client.Application.ensure_twitch_started()

    if is_pid(caller) do
      send(caller, {:twitch_oauth_token, data})
    end
  end

  defp resolve_port(opts) do
    case Keyword.get(opts, :port) do
      port when is_integer(port) and port > 0 ->
        port

      _ ->
        case System.get_env("TF2_WEB_PORT") do
          nil ->
            @default_port

          env_port ->
            case Integer.parse(env_port) do
              {parsed, ""} when parsed > 0 -> parsed
              _ -> @default_port
            end
        end
    end
  end

  defp valid_string?(str) when is_binary(str) do
    String.trim(str) != ""
  end

  defp valid_string?(_), do: false
end
