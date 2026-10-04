defmodule TF2Client.SetupWizardTest do
  use ExUnit.Case, async: false

  alias TF2Client.Config
  alias TF2Client.SetupWizard

  test "automatic_setup? returns false in test environment" do
    assert SetupWizard.automatic_setup?() == false
  end

  test "automatic setup does not require terminal detection outside tests and IEx" do
    previous_env = Mix.env()

    try do
      Mix.env(:prod)

      ExUnit.CaptureIO.capture_io(fn ->
        assert SetupWizard.automatic_setup?()
      end)
    after
      Mix.env(previous_env)
    end
  end

  @tag :tmp_dir
  test "startup stops when first-run input is unavailable", %{tmp_dir: tmp_dir} do
    previous_env = Mix.env()
    previous_args = System.argv()
    previous_config_path = System.get_env("TF_CONFIG_PATH")
    previous_user = System.get_env("TWITCH_BOT_USER")
    config_path = Path.join(tmp_dir, "config.json")
    System.put_env("TF_CONFIG_PATH", config_path)
    System.put_env("TWITCH_BOT_USER", " ")
    System.argv([])

    try do
      Mix.env(:prod)

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          ExUnit.CaptureIO.capture_io("", fn ->
            assert {:error, {:setup_failed, :eof}} = TF2Client.Application.start(:normal, [])
          end)
        end)

      assert log =~ "Client setup could not complete"
      assert log =~ "setup command in a terminal"
      refute File.exists?(config_path)
    after
      Mix.env(previous_env)
      System.argv(previous_args)

      case previous_config_path do
        nil -> System.delete_env("TF_CONFIG_PATH")
        value -> System.put_env("TF_CONFIG_PATH", value)
      end

      case previous_user do
        nil -> System.delete_env("TWITCH_BOT_USER")
        value -> System.put_env("TWITCH_BOT_USER", value)
      end
    end
  end

  test "configured users continue without prompting" do
    config = %Config{bot_user: "my_bot", channels: ["my_channel"]}

    output =
      ExUnit.CaptureIO.capture_io(fn ->
        assert {:ok, ^config} = SetupWizard.ensure_configured(config)
      end)

    assert output == ""
  end

  test "a disabled bot does not require setup" do
    config = %Config{enable_bot: false}

    output =
      ExUnit.CaptureIO.capture_io(fn ->
        assert {:ok, ^config} = SetupWizard.ensure_configured(config)
      end)

    assert output == ""
  end

  test "ensure_configured/1 returns error gracefully when input is EOF" do
    # In test environment, standard input is closed or simulated, so reading input returns :eof or unsupported
    {:ok, string_io} = StringIO.open("")
    previous_leader = Process.group_leader()
    Process.group_leader(self(), string_io)

    try do
      assert {:error, _reason} = SetupWizard.ensure_configured(%Config{})
    after
      Process.group_leader(self(), previous_leader)
      StringIO.close(string_io)
    end
  end

  test "ensure_configured/1 successfully saves configuration with provided inputs" do
    inputs = "2\nmy_stream_channel\nmy_bot_user\nmy_client_id\nmy_client_secret\noauth:manual_token\n"
    {:ok, string_io} = StringIO.open(inputs)
    previous_leader = Process.group_leader()
    Process.group_leader(self(), string_io)

    test_dir = Path.join(__DIR__, "../tmp/wizard_test")
    File.mkdir_p!(test_dir)
    test_config_path = Path.join(test_dir, "config.json")
    System.put_env("TF_CONFIG_PATH", test_config_path)

    try do
      assert {:ok, %Config{} = config} = SetupWizard.ensure_configured(%Config{})
      assert config.channels == ["my_stream_channel"]
      assert config.bot_user == "my_bot_user"
      assert config.client_id == "my_client_id"
      assert config.client_secret == "my_client_secret"
      assert config.bot_oauth == "oauth:manual_token"
      assert {:ok, saved_config} = Config.load(test_config_path)
      assert saved_config.bot_oauth == "oauth:manual_token"
      assert File.exists?(test_config_path)
    after
      Process.group_leader(self(), previous_leader)
      StringIO.close(string_io)
      System.delete_env("TF_CONFIG_PATH")
      File.rm_rf(test_dir)
    end
  end

  test "ensure_configured/1 successfully saves minimal configuration with only channel name and defaults" do
    inputs = "\nmy_stream_channel\n\n"
    {:ok, string_io} = StringIO.open(inputs)
    previous_leader = Process.group_leader()
    Process.group_leader(self(), string_io)

    test_dir = Path.join(__DIR__, "../tmp/wizard_test_minimal")
    File.mkdir_p!(test_dir)
    test_config_path = Path.join(test_dir, "config.json")
    System.put_env("TF_CONFIG_PATH", test_config_path)

    try do
      assert {:ok, %Config{} = config} = SetupWizard.ensure_configured(%Config{})
      assert config.channels == ["my_stream_channel"]
      assert config.bot_user == "my_stream_channel"
      assert config.client_id == nil
      assert config.client_secret == nil
      assert config.bot_oauth == nil
      {_input, output} = StringIO.contents(string_io)
      assert output =~ "Log in to Twitch as my_stream_channel"
      refute output =~ "Twitch Client ID (optional"
      refute output =~ "Twitch Client Secret (optional"
      refute output =~ "Twitch Bot OAuth IRC token (optional"
      assert File.exists?(test_config_path)
    after
      Process.group_leader(self(), previous_leader)
      StringIO.close(string_io)
      System.delete_env("TF_CONFIG_PATH")
      File.rm_rf(test_dir)
    end
  end

  @tag :tmp_dir
  test "browser selection retries invalid choices and replaces manual credentials", %{tmp_dir: tmp_dir} do
    config_path = Path.join(tmp_dir, "config.json")
    previous_path = System.get_env("TF_CONFIG_PATH")
    System.put_env("TF_CONFIG_PATH", config_path)

    existing_config = %Config{
      channels: ["streamer"],
      bot_user: "separate_bot",
      client_id: "custom_client",
      client_secret: "custom_secret",
      bot_oauth: "oauth:old_token",
      redirect_uri: "http://localhost:9999/custom",
      debug: true
    }

    try do
      output =
        ExUnit.CaptureIO.capture_io("invalid\n1\n\n\n", fn ->
          assert {:ok, config} = SetupWizard.run(existing_config)
          assert config.channels == ["streamer"]
          assert config.bot_user == "separate_bot"
          assert config.client_id == nil
          assert config.client_secret == nil
          assert config.bot_oauth == nil
          assert config.redirect_uri == %Config{}.redirect_uri
          assert config.debug
          saved = Jason.decode!(File.read!(config_path))
          assert saved["bot_user"] == "separate_bot"
          assert saved["debug"]
          refute Map.has_key?(saved, "client_id")
          refute Map.has_key?(saved, "client_secret")
          refute Map.has_key?(saved, "bot_oauth")
        end)

      assert output =~ "Please enter 1 for browser authentication or 2 for manual configuration."
      assert output =~ "Log in to Twitch as separate_bot"
    after
      case previous_path do
        nil -> System.delete_env("TF_CONFIG_PATH")
        value -> System.put_env("TF_CONFIG_PATH", value)
      end
    end
  end

  @tag :tmp_dir
  test "manual setup preserves existing values when optional fields are skipped", %{tmp_dir: tmp_dir} do
    config_path = Path.join(tmp_dir, "config.json")
    previous_path = System.get_env("TF_CONFIG_PATH")
    System.put_env("TF_CONFIG_PATH", config_path)

    existing_config = %Config{
      channels: ["streamer"],
      bot_user: "separate_bot",
      client_id: "custom_client",
      client_secret: "custom_secret",
      bot_oauth: "oauth:existing_token"
    }

    try do
      ExUnit.CaptureIO.capture_io("2\n\n\n\n\n\n", fn ->
        assert {:ok, ^existing_config} = SetupWizard.run(existing_config)
        assert {:ok, ^existing_config} = Config.load(config_path)
      end)
    after
      case previous_path do
        nil -> System.delete_env("TF_CONFIG_PATH")
        value -> System.put_env("TF_CONFIG_PATH", value)
      end
    end
  end

  @tag :tmp_dir
  test "input ending partway through either branch does not save configuration", %{tmp_dir: tmp_dir} do
    config_path = Path.join(tmp_dir, "config.json")
    previous_path = System.get_env("TF_CONFIG_PATH")
    System.put_env("TF_CONFIG_PATH", config_path)

    try do
      ExUnit.CaptureIO.capture_io("1\nstreamer\n", fn ->
        assert {:error, :eof} = SetupWizard.run(%Config{})
      end)

      refute File.exists?(config_path)

      ExUnit.CaptureIO.capture_io("2\nstreamer\n\n", fn ->
        assert {:error, :eof} = SetupWizard.run(%Config{})
      end)

      refute File.exists?(config_path)
    after
      case previous_path do
        nil -> System.delete_env("TF_CONFIG_PATH")
        value -> System.put_env("TF_CONFIG_PATH", value)
      end
    end
  end
end
