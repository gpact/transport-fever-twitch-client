defmodule TF2Client.RequestTracker do
  @moduledoc false

  use GenServer

  @name __MODULE__

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: @name)
  end

  def track(order_id, data) when is_binary(order_id) and is_map(data) do
    GenServer.call(@name, {:track, order_id, Map.put_new(data, :tracked_at, System.os_time(:second))})
  end

  def untrack(order_id) when is_binary(order_id) do
    GenServer.call(@name, {:untrack, order_id})
  end

  def get(order_id) when is_binary(order_id) do
    GenServer.call(@name, {:get, order_id})
  end

  def pending_ids do
    GenServer.call(@name, :pending_ids)
  end

  @impl GenServer
  def init(state), do: {:ok, state}

  @impl GenServer
  def handle_call({:track, order_id, data}, _from, state) do
    {:reply, :ok, Map.put(state, order_id, data)}
  end

  def handle_call({:untrack, order_id}, _from, state) do
    {data, state} = Map.pop(state, order_id)
    {:reply, data, state}
  end

  def handle_call({:get, order_id}, _from, state) do
    {:reply, Map.get(state, order_id), state}
  end

  def handle_call(:pending_ids, _from, state) do
    {:reply, Map.keys(state), state}
  end
end
