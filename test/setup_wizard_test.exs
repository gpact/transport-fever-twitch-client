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
    inputs = "my_stream_channel\nmy_bot_user\nmy_client_id\nmy_client_secret\n\n"
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
      assert File.exists?(test_config_path)
    after
      Process.group_leader(self(), previous_leader)
      StringIO.close(string_io)
      System.delete_env("TF_CONFIG_PATH")
      File.rm_rf(test_dir)
    end
  end

  test "ensure_configured/1 successfully saves minimal configuration with only channel name and defaults" do
    inputs = "my_stream_channel\n\n\n\n\n"
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
      assert File.exists?(test_config_path)
    after
      Process.group_leader(self(), previous_leader)
      StringIO.close(string_io)
      System.delete_env("TF_CONFIG_PATH")
      File.rm_rf(test_dir)
    end
  end
end
