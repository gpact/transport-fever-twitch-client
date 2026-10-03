defmodule TF2Client.GameBridge do
  @moduledoc false

  alias TF2Client.Lua

  @schema_version 1
  @game_files_env "TF_INTEGRATION_GAME_FILES"
  @game_state_file "gameState.json"
  @default_home_folder ".transport_fever"
  @default_temp_folder "transport_fever"

  def requests_dir do
    case env_value(@game_files_env) do
      {:ok, dir} -> dir
      :error -> default_requests_dir()
    end
  end

  def ensure_requests_dir do
    File.mkdir_p(requests_dir())
  end

  def requests_path(save_uuid), do: Path.join(requests_dir(), "requests_#{save_uuid}.txt")

  # All queue mutations share a lock, including immediate and delayed submissions.
  # Atomic replacement lets the mod read either complete version of the index.
  def complete_request(order_id, save_uuid) when is_binary(save_uuid) do
    update_requests(save_uuid, fn ids -> Enum.reject(ids, &(&1 == order_id)) end)
  end

  def complete_request(_order_id, _save_uuid), do: {:error, :save_uuid_missing}
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
    game_version = Atom.to_string(TF2Client.TransportFever.version())

    payload = %{
      schema_version: @schema_version,
      game_version: game_version,
      order: %{
        order_id: order_id,
        request_type: type,
        type: type,
        username: username,
        save_uuid: save_uuid,
        game_version: game_version,
        timestamp: System.os_time(:second),
        params: Map.merge(%{username: username}, wire_params(params))
      }
    }

    lua = "return " <> Lua.encode(payload) <> "\n"

    with :ok <- ensure_requests_dir(),
         :ok <- File.write(order_lua_path(order_id), lua),
         :ok <- update_requests(save_uuid, fn ids -> ids ++ [order_id] end) do
      {:ok, order_id}
    else
      {:error, reason} -> {:error, {:file_error, reason}}
    end
  end

  defp update_requests(save_uuid, update) do
    case Regex.match?(~r/\A[A-Za-z0-9_-]+\z/, save_uuid) do
      true ->
        path = requests_path(save_uuid)
        :global.trans({{__MODULE__, path}, self()}, fn -> rewrite_requests(path, update) end)

      false ->
        {:error, :invalid_save_uuid}
    end
  end

  defp rewrite_requests(path, update) do
    with {:ok, ids} <- read_requests(path) do
      contents = Enum.map(update.(ids), &(&1 <> "\n"))
      temporary = path <> ".tmp"

      with :ok <- File.write(temporary, contents),
           :ok <- File.rename(temporary, path) do
        :ok
      else
        error ->
          File.rm(temporary)
          error
      end
    end
  end

  defp read_requests(path) do
    case File.read(path) do
      {:ok, contents} -> {:ok, String.split(contents, "\n", trim: true)}
      {:error, :enoent} -> {:ok, []}
      error -> error
    end
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

  defp wire_params(params) when is_map(params) do
    params
    |> maybe_translate_wire_field(:carrier, &TF2Client.TransportFever.wire_carrier/1)
    |> maybe_translate_wire_field(:cargo, &TF2Client.TransportFever.wire_cargo/1)
  end

  defp maybe_translate_wire_field(params, key, transform) do
    case Map.get(params, key) do
      value when is_binary(value) -> Map.put(params, key, transform.(value))
      _ -> params
    end
  end
end
