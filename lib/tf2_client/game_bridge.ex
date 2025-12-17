defmodule TF2Client.GameBridge do
  @moduledoc false

  alias TF2Client.Lua

  @schema_version 1
  @requests_file "requests.txt"
  @game_state_file "gameState.json"

  def requests_dir do
    System.get_env("TF2_INTEGRATION_GAME_FILES") || "/tmp/tf2"
  end

  def requests_path, do: Path.join(requests_dir(), @requests_file)
  def game_state_path, do: Path.join(requests_dir(), @game_state_file)
  def order_lua_path(order_id), do: Path.join(requests_dir(), "#{order_id}.lua")
  def response_json_path(order_id), do: Path.join(requests_dir(), "#{order_id}.json")

  def submit(type, username, params) when is_binary(type) and is_binary(username) and is_map(params) do
    with {:ok, save_uuid} <- read_save_uuid(),
         {:ok, order_id} <- write_order(type, username, save_uuid, params) do
      {:ok, order_id}
    end
  end

  def read_save_uuid do
    case File.read(game_state_path()) do
      {:ok, json} ->
        with {:ok, %{} = decoded} <- Jason.decode(json) do
          case Map.get(decoded, "save_uuid") do
            value when is_binary(value) and value != "" -> {:ok, value}
            _ -> {:error, :save_uuid_missing}
          end
        else
          _ -> {:error, :game_state_invalid}
        end

      {:error, :enoent} ->
        {:error, :game_state_missing}

      {:error, reason} ->
        {:error, {:file_error, reason}}
    end
  end

  defp write_order(type, username, save_uuid, params) do
    order_id = new_order_id()
    dir = requests_dir()

    payload = %{
      schema_version: @schema_version,
      order: %{
        order_id: order_id,
        request_type: type,
        type: type,
        username: username,
        save_uuid: save_uuid,
        timestamp: System.os_time(:second),
        params: Map.merge(%{username: username}, params)
      }
    }

    lua = "return " <> Lua.encode(payload) <> "\n"

    with :ok <- File.mkdir_p(dir),
         :ok <- File.write(order_lua_path(order_id), lua),
         :ok <- append_request_id(order_id) do
      {:ok, order_id}
    else
      {:error, reason} -> {:error, {:file_error, reason}}
    end
  end

  defp append_request_id(order_id) do
    File.write(requests_path(), "#{order_id}\n", [:append])
  end

  defp new_order_id do
    :crypto.strong_rand_bytes(16)
    |> Base.encode16(case: :lower)
  end
end
