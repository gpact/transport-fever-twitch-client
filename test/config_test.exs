defmodule TF2Client.ConfigTest do
  use ExUnit.Case, async: false

  alias TF2Client.Config

  @test_config_dir Path.join(__DIR__, "../tmp/test_config")

  setup do
    File.mkdir_p!(@test_config_dir)
    config_file = Path.join(@test_config_dir, "config.json")
    System.put_env("TF_CONFIG_PATH", config_file)

    saved_env = %{
      "TWITCH_BOT_USER" => System.get_env("TWITCH_BOT_USER"),
      "TWITCH_CHANNELS" => System.get_env("TWITCH_CHANNELS"),
      "TWITCH_CLIENT_ID" => System.get_env("TWITCH_CLIENT_ID"),
      "TWITCH_CLIENT_SECRET" => System.get_env("TWITCH_CLIENT_SECRET"),
      "TWITCH_DEBUG" => System.get_env("TWITCH_DEBUG"),
      "TF_ENABLE_TWITCH_BOT" => System.get_env("TF_ENABLE_TWITCH_BOT")
    }

    Enum.each(Map.keys(saved_env), &System.delete_env/1)

    on_exit(fn ->
      System.delete_env("TF_CONFIG_PATH")

      Enum.each(saved_env, fn
        {k, nil} -> System.delete_env(k)
        {k, v} -> System.put_env(k, v)
      end)

      File.rm_rf(@test_config_dir)
    end)

    {:ok, config_file: config_file}
  end

  test "returns default config when file does not exist", %{config_file: config_file} do
    assert {:ok, %Config{} = config} = Config.load(config_file)
    assert config.bot_user == nil
    assert config.channels == []
    assert config.debug == false
    assert config.redirect_uri == "http://localhost:4000/oauth/callback"
    assert config.enable_bot == true
    assert Config.configured?(config) == false
  end

  test "loads config from json file with snake_case keys", %{config_file: config_file} do
    json = """
    {
      "bot_user": "my_test_bot",
      "channels": ["streamer_one", "streamer_two"],
      "client_id": "test_client_id",
      "client_secret": "test_client_secret",
      "debug": true
    }
    """

    File.write!(config_file, json)

    assert {:ok, %Config{} = config} = Config.load(config_file)
    assert config.bot_user == "my_test_bot"
    assert config.channels == ["streamer_one", "streamer_two"]
    assert config.client_id == "test_client_id"
    assert config.client_secret == "test_client_secret"
    assert config.debug == true
    assert Config.configured?(config) == true
  end

  test "loads config from json file with twitch_ prefixed keys", %{config_file: config_file} do
    json = """
    {
      "twitch_bot_user": "prefixed_bot",
      "twitch_channels": "streamer_three, streamer_four",
      "twitch_client_id": "prefixed_id",
      "twitch_client_secret": "prefixed_secret",
      "twitch_debug": "true"
    }
    """

    File.write!(config_file, json)

    assert {:ok, %Config{} = config} = Config.load(config_file)
    assert config.bot_user == "prefixed_bot"
    assert config.channels == ["streamer_three", "streamer_four"]
    assert config.client_id == "prefixed_id"
    assert config.client_secret == "prefixed_secret"
    assert config.debug == true
  end

  test "environment variables take precedence over config file", %{config_file: config_file} do
    json = """
    {
      "bot_user": "file_bot",
      "channels": ["file_channel"],
      "client_id": "file_id",
      "client_secret": "file_secret",
      "debug": false
    }
    """

    File.write!(config_file, json)

    System.put_env("TWITCH_BOT_USER", "env_bot")
    System.put_env("TWITCH_CHANNELS", "env_channel_1, env_channel_2")
    System.put_env("TWITCH_DEBUG", "true")

    assert {:ok, %Config{} = config} = Config.load(config_file)
    assert config.bot_user == "env_bot"
    assert config.channels == ["env_channel_1", "env_channel_2"]
    assert config.client_id == "file_id"
    assert config.client_secret == "file_secret"
    assert config.debug == true
  end

  test "saves config struct to json file atomically", %{config_file: config_file} do
    config = %Config{
      bot_user: "saved_bot",
      channels: ["saved_channel"],
      client_id: "saved_client",
      client_secret: "saved_secret",
      debug: false
    }

    assert :ok = Config.save(config, config_file)

    assert File.exists?(config_file)
    assert {:ok, decoded} = Jason.decode(File.read!(config_file))
    assert decoded["bot_user"] == "saved_bot"
    assert decoded["channels"] == ["saved_channel"]
    assert decoded["client_id"] == "saved_client"
    assert decoded["client_secret"] == "saved_secret"
  end

  test "getter helpers fetch credentials from config or env", %{config_file: config_file} do
    json = """
    {
      "client_id": "helper_id",
      "client_secret": "helper_secret"
    }
    """

    File.write!(config_file, json)

    assert Config.client_id() == "helper_id"
    assert Config.client_secret() == "helper_secret"
    assert Config.redirect_uri() == "http://localhost:4000/oauth/callback"

    System.put_env("TWITCH_CLIENT_ID", "override_id")
    assert Config.client_id() == "override_id"
  end

  test "client_id falls back to default project client_id when not configured", %{config_file: config_file} do
    File.write!(config_file, "{}")
    assert Config.client_id() == "l4my2fg4doyt5rpr0sow94d441jxxl"
  end

  test "client_secret returns nil and implicit_flow? returns true when not configured", %{config_file: config_file} do
    File.write!(config_file, "{}")
    assert Config.client_secret() == nil
    assert Config.implicit_flow?() == true
  end

  test "implicit_flow? returns false when client_secret is configured", %{config_file: config_file} do
    json = """
    {
      "client_secret": "my_secret"
    }
    """

    File.write!(config_file, json)
    assert Config.client_secret() == "my_secret"
    assert Config.implicit_flow?() == false
  end

  test "summary reflects default client_id and browser login status", %{config_file: config_file} do
    File.write!(config_file, "{}")
    summary = Config.summary()
    assert String.contains?(summary, "Transport Fever Twitch Bot - Configuration")
    refute String.contains?(summary, "Transport Fever 2")
    assert String.contains?(summary, "project default (l4my2fg4doyt5rpr0sow94d441jxxl)")
    assert String.contains?(summary, "not set (using browser login)")
  end

  test "supports TF_ prefixed env variables" do
    System.put_env("TF_CONFIG_PATH", "/tmp/custom_tf_config.json")
    assert Config.config_path() == "/tmp/custom_tf_config.json"
    System.delete_env("TF_CONFIG_PATH")
  end
end
