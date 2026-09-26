defmodule TF2Client.SetupWizardTest do
  use ExUnit.Case, async: true

  alias TF2Client.Config
  alias TF2Client.SetupWizard

  test "interactive? returns false in test environment" do
    assert SetupWizard.interactive?() == false
  end

  test "run/1 returns error gracefully when input is EOF" do
    # In test environment, standard input is closed or simulated, so reading input returns :eof or unsupported
    {:ok, string_io} = StringIO.open("")
    previous_leader = Process.group_leader()
    Process.group_leader(self(), string_io)

    try do
      assert {:error, _reason} = SetupWizard.run(%Config{})
    after
      Process.group_leader(self(), previous_leader)
      StringIO.close(string_io)
    end
  end

  test "run/1 successfully saves configuration with provided inputs" do
    inputs = "my_stream_channel\nmy_bot_user\nmy_client_id\nmy_client_secret\n\n"
    {:ok, string_io} = StringIO.open(inputs)
    previous_leader = Process.group_leader()
    Process.group_leader(self(), string_io)

    test_dir = Path.join(__DIR__, "../tmp/wizard_test")
    File.mkdir_p!(test_dir)
    test_config_path = Path.join(test_dir, "config.json")
    System.put_env("TF_CONFIG_PATH", test_config_path)

    try do
      assert {:ok, %Config{} = config} = SetupWizard.run(%Config{})
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

  test "run/1 successfully saves minimal configuration with only channel name and defaults" do
    inputs = "my_stream_channel\n\n\n\n\n"
    {:ok, string_io} = StringIO.open(inputs)
    previous_leader = Process.group_leader()
    Process.group_leader(self(), string_io)

    test_dir = Path.join(__DIR__, "../tmp/wizard_test_minimal")
    File.mkdir_p!(test_dir)
    test_config_path = Path.join(test_dir, "config.json")
    System.put_env("TF_CONFIG_PATH", test_config_path)

    try do
      assert {:ok, %Config{} = config} = SetupWizard.run(%Config{})
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
