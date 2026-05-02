defmodule TF2Client.GameBridgeTest do
  use ExUnit.Case, async: false

  alias TF2Client.GameBridge

  @game_files_env "TF2_INTEGRATION_GAME_FILES"
  @path_envs [
    @game_files_env,
    "HOME",
    "USERPROFILE",
    "HOMEDRIVE",
    "HOMEPATH",
    "TMPDIR",
    "TEMP",
    "TMP",
    "tmp"
  ]

  setup do
    previous_env = capture_env(@path_envs)

    on_exit(fn -> restore_env(previous_env) end)

    :ok
  end

  test "uses configured game files directory when it is non-empty" do
    dir = put_game_files_dir()

    assert GameBridge.requests_dir() == dir
  end

  test "uses home .tf2 directory when configured game files directory is empty" do
    home_dir = put_home_dir()
    System.put_env(@game_files_env, "")

    expected = Path.join(home_dir, ".tf2")

    assert GameBridge.requests_dir() == expected
  end

  test "creates default home directory before reading game state" do
    home_dir = put_home_dir()
    System.delete_env(@game_files_env)

    expected = Path.join(home_dir, ".tf2")

    assert {:error, :game_state_missing} = GameBridge.read_save_uuid()
    assert File.dir?(expected)
  end

  test "uses temp fallback when game files and home directories are missing" do
    temp_dir = temp_dir("tf2-temp")
    System.put_env(@game_files_env, "")
    delete_home_env()
    System.put_env("TMPDIR", "")
    System.put_env("TEMP", temp_dir)
    System.put_env("TMP", temp_dir("tf2-ignored-tmp"))
    System.put_env("tmp", temp_dir("tf2-ignored-lower-tmp"))

    assert GameBridge.requests_dir() == Path.join(temp_dir, "tf2")
  end

  test "writes lua order file and appends to requests.txt" do
    dir = put_game_files_dir()
    File.write!(Path.join(dir, "gameState.json"), ~s({"save_uuid":"save-123"}))

    assert {:ok, order_id} = GameBridge.submit("COMPANY", "someuser", %{company_name: "Some Co"})
    assert byte_size(order_id) == 32
    assert File.exists?(GameBridge.order_lua_path(order_id))
    assert File.exists?(GameBridge.requests_path())

    requests = File.read!(GameBridge.requests_path())
    assert String.contains?(requests, order_id)

    lua = File.read!(GameBridge.order_lua_path(order_id))
    assert String.contains?(lua, ~s(schema_version))
    assert String.contains?(lua, ~s(request_type = "COMPANY"))
    assert String.contains?(lua, ~s(username = "someuser"))
    assert String.contains?(lua, ~s(save_uuid = "save-123"))
    assert String.contains?(lua, ~s(company_name = "Some Co"))
  end

  defp put_game_files_dir do
    dir = temp_dir("tf2-client-test")
    File.mkdir_p!(dir)
    System.put_env(@game_files_env, dir)
    on_exit(fn -> File.rm_rf(dir) end)
    dir
  end

  defp put_home_dir do
    home_dir = temp_dir("tf2-home")
    File.mkdir_p!(home_dir)
    put_platform_home_env(home_dir)
    on_exit(fn -> File.rm_rf(home_dir) end)
    home_dir
  end

  defp put_platform_home_env(home_dir) do
    case :os.type() do
      {:win32, _name} -> System.put_env("USERPROFILE", home_dir)
      _other -> System.put_env("HOME", home_dir)
    end
  end

  defp delete_home_env do
    System.delete_env("HOME")
    System.delete_env("USERPROFILE")
    System.delete_env("HOMEDRIVE")
    System.delete_env("HOMEPATH")
  end

  defp temp_dir(prefix) do
    random_bytes = :crypto.strong_rand_bytes(6)
    suffix = Base.encode16(random_bytes, case: :lower)
    Path.join(System.tmp_dir!(), "#{prefix}-#{suffix}")
  end

  defp capture_env(env_names) do
    Enum.reduce(env_names, %{}, fn env_name, env ->
      Map.put(env, env_name, System.get_env(env_name))
    end)
  end

  defp restore_env(previous_env) do
    Enum.each(previous_env, fn
      {env_name, nil} -> System.delete_env(env_name)
      {env_name, value} -> System.put_env(env_name, value)
    end)
  end
end
