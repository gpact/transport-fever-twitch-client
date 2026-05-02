defmodule TF2Client.GameBridge do
  @moduledoc false

  alias TF2Client.Lua

  @schema_version 1
  @game_files_env "TF2_INTEGRATION_GAME_FILES"
  @requests_file "requests.txt"
  @game_state_file "gameState.json"
  @default_home_folder ".tf2"
  @default_temp_folder "tf2"

  def requests_dir do
    case env_value(@game_files_env) do
      {:ok, dir} -> dir
      :error -> default_requests_dir()
    end
  end

  def ensure_requests_dir do
    File.mkdir_p(requests_dir())
  end

  def requests_path, do: Path.join(requests_dir(), @requests_file)
  def game_state_path, do: Path.join(requests_dir(), @game_state_file)
  def order_lua_path(order_id), do: Path.join(requests_dir(), "#{order_id}.lua")
  def response_json_path(order_id), do: Path.join(requests_dir(), "#{order_id}.json")

  def submit(type, username, params) when is_binary(type) and is_binary(username) and is_map(params) do
    with {:ok, save_uuid} <- read_save_uuid(),
         {:ok, order_id} <- write_order(new_order_id(), type, username, save_uuid, params) do
      {:ok, order_id}
    end
  end

  def submit_with_order_id(order_id, type, username, save_uuid, params)
      when is_binary(order_id) and is_binary(type) and is_binary(username) and
             is_binary(save_uuid) and is_map(params) do
    write_order(order_id, type, username, save_uuid, params)
  end

  def read_save_uuid do
    case ensure_requests_dir() do
      :ok -> read_save_uuid_file()
      {:error, reason} -> {:error, {:file_error, reason}}
    end
  end

  defp read_save_uuid_file do
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

  defp write_order(order_id, type, username, save_uuid, params) do
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

    with :ok <- ensure_requests_dir(),
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

  defp default_requests_dir do
    case home_dir() do
      {:ok, home_dir} -> Path.join(home_dir, @default_home_folder)
      :error -> Path.join(temp_dir(), @default_temp_folder)
    end
  end

  defp home_dir do
    case :os.type() do
      {:win32, _name} -> windows_home_dir()
      _other -> env_value("HOME")
    end
  end

  defp windows_home_dir do
    case env_value("USERPROFILE") do
      {:ok, home_dir} -> {:ok, home_dir}
      :error -> windows_drive_home_dir()
    end
  end

  defp windows_drive_home_dir do
    case {env_value("HOMEDRIVE"), env_value("HOMEPATH")} do
      {{:ok, home_drive}, {:ok, home_path}} -> {:ok, home_drive <> home_path}
      _other -> env_value("HOME")
    end
  end

  defp temp_dir do
    case first_env_value(["TMPDIR", "TEMP", "TMP", "tmp"]) do
      {:ok, temp_dir} -> temp_dir
      :error -> "/tmp"
    end
  end

  defp first_env_value([env_name | rest]) do
    case env_value(env_name) do
      {:ok, value} -> {:ok, value}
      :error -> first_env_value(rest)
    end
  end

  defp first_env_value([]), do: :error

  defp env_value(env_name) do
    case System.get_env(env_name) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _other -> :error
    end
  end

  defp new_order_id do
    random_bytes = :crypto.strong_rand_bytes(16)
    Base.encode16(random_bytes, case: :lower)
  end
end
