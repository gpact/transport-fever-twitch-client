defmodule TF2Client.Twitch.FileTokenStoreTest do
  use ExUnit.Case, async: false

  alias TF2Client.Twitch.FileTokenStore

  @test_dir Path.join(__DIR__, "../tmp/test_tokens")
  @test_token_file Path.join(@test_dir, "test_tokens.json")

  setup do
    File.mkdir_p!(@test_dir)
    System.put_env("TF2_TOKENS_PATH", @test_token_file)

    on_exit(fn ->
      System.delete_env("TF2_TOKENS_PATH")
      File.rm_rf(@test_dir)
    end)

    :ok
  end

  test "returns :error when token file does not exist" do
    assert FileTokenStore.load() == :error
  end

  test "saves and loads authorization code flow tokens with refresh_token" do
    now = System.os_time(:second)

    tokens = %{
      access_token: "test_access_code_flow",
      refresh_token: "test_refresh_code_flow",
      expires_at: now + 3600
    }

    assert :ok = FileTokenStore.save(tokens)
    assert {:ok, loaded} = FileTokenStore.load()
    assert loaded.access_token == "test_access_code_flow"
    assert loaded.refresh_token == "test_refresh_code_flow"
    assert loaded.expires_at == now + 3600
  end

  test "saves and loads implicit grant tokens without refresh_token" do
    now = System.os_time(:second)

    tokens = %{
      access_token: "test_implicit_token",
      refresh_token: nil,
      expires_at: now + 5_184_000
    }

    assert :ok = FileTokenStore.save(tokens)
    assert {:ok, loaded} = FileTokenStore.load()
    assert loaded.access_token == "test_implicit_token"
    assert loaded.refresh_token == nil
    assert loaded.expires_at == now + 5_184_000
  end

  test "defaults expires_at to ~60 days if missing on save" do
    tokens = %{
      access_token: "test_token_no_expiry",
      refresh_token: nil
    }

    now = System.os_time(:second)
    assert :ok = FileTokenStore.save(tokens)
    assert {:ok, loaded} = FileTokenStore.load()
    assert loaded.access_token == "test_token_no_expiry"
    assert loaded.expires_at >= now + 5_180_000
  end

  test "delete removes the token file" do
    FileTokenStore.save(%{access_token: "to_delete"})
    assert File.exists?(@test_token_file)

    assert :ok = FileTokenStore.delete()
    refute File.exists?(@test_token_file)
    assert FileTokenStore.load() == :error
  end
end
