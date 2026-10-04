defmodule TF2Client.TwitchConfigTest do
  use ExUnit.Case, async: false

  alias TF2Client.Config
  alias TF2Client.TwitchConfig

  test "returns error when TF_ENABLE_TWITCH_BOT is disabled" do
    config = %Config{enable_bot: false}
    assert TwitchConfig.from_config(config) == {:error, "TF_ENABLE_TWITCH_BOT disabled"}
  end

  test "returns error when bot username is missing" do
    config = %Config{bot_user: nil, channels: ["mychannel"]}
    assert {:error, msg} = TwitchConfig.from_config(config)
    assert String.contains?(msg, "missing bot username")
  end

  test "returns error when channels are empty" do
    config = %Config{bot_user: "mybot", channels: []}
    assert {:error, msg} = TwitchConfig.from_config(config)
    assert String.contains?(msg, "missing channels")
  end

  test "successfully configures bot with explicit bot_oauth" do
    config = %Config{
      bot_user: "MyBot",
      channels: ["ChannelOne", "ChannelTwo"],
      mod_channels: ["ChannelOne"],
      debug: true,
      bot_oauth: "oauth:12345abcdef"
    }

    assert {:ok, opts} = TwitchConfig.from_config(config, &valid_token_response/2)
    assert Keyword.get(opts, :user) == "mybot"
    assert Keyword.get(opts, :pass) == "oauth:12345abcdef"
    assert Keyword.get(opts, :channels) == ["channelone", "channeltwo"]
    assert Keyword.get(opts, :mod_channels) == ["channelone"]
    assert Keyword.get(opts, :debug) == true
  end

  test "ensures oauth prefix is added to raw bot_oauth token" do
    config = %Config{
      bot_user: "MyBot",
      channels: ["mychannel"],
      bot_oauth: "raw_token_without_prefix"
    }

    assert {:ok, opts} = TwitchConfig.from_config(config, &valid_token_response/2)
    assert Keyword.get(opts, :pass) == "oauth:raw_token_without_prefix"
  end

  test "invalid manual credentials stop before starting IRC" do
    config = %Config{bot_user: "mybot", channels: ["channel"], bot_oauth: "oauth:invalid"}
    request = fn _request, _finch -> {:ok, %Finch.Response{status: 401}} end

    assert {:error, message} = TwitchConfig.from_config(config, request)
    assert message =~ "expired or was revoked"
    assert message =~ "Update your manual OAuth token"
  end

  @tag :tmp_dir
  test "revoked saved credentials trigger reauthorization instead of being reused", %{tmp_dir: tmp_dir} do
    previous_path = System.get_env("TF_TOKENS_PATH")
    System.put_env("TF_TOKENS_PATH", Path.join(tmp_dir, "tokens.json"))

    try do
      :ok = TF2Client.Twitch.FileTokenStore.save(%{access_token: "revoked", expires_at: System.os_time(:second) + 3600})
      config = %Config{bot_user: "mybot", channels: ["channel"]}
      request = fn _request, _finch -> {:ok, %Finch.Response{status: 401}} end

      output =
        ExUnit.CaptureIO.capture_io(fn ->
          # Browser launching is disabled in tests; reaching this error proves reauthorization was requested.
          assert {:error, "missing Twitch OAuth tokens; run oauth.bootstrap"} =
                   TwitchConfig.from_config(config, request)
        end)

      assert output =~ "expired or was revoked"
      assert :error = TF2Client.Twitch.FileTokenStore.load()
    after
      restore_tokens_path(previous_path)
    end
  end

  @tag :tmp_dir
  test "temporary validation failures preserve saved credentials", %{tmp_dir: tmp_dir} do
    previous_path = System.get_env("TF_TOKENS_PATH")
    System.put_env("TF_TOKENS_PATH", Path.join(tmp_dir, "tokens.json"))

    try do
      :ok = TF2Client.Twitch.FileTokenStore.save(%{access_token: "saved", expires_at: System.os_time(:second) + 3600})
      config = %Config{bot_user: "mybot", channels: ["channel"]}
      request = fn _request, _finch -> {:error, :timeout} end

      assert {:error, message} = TwitchConfig.from_config(config, request)
      assert message =~ "Check your connection"
      assert {:ok, %{access_token: "saved"}} = TF2Client.Twitch.FileTokenStore.load()
    after
      restore_tokens_path(previous_path)
    end
  end

  @tag :tmp_dir
  test "saved credentials for the wrong account trigger reauthorization", %{tmp_dir: tmp_dir} do
    previous_path = System.get_env("TF_TOKENS_PATH")
    System.put_env("TF_TOKENS_PATH", Path.join(tmp_dir, "tokens.json"))

    try do
      :ok = TF2Client.Twitch.FileTokenStore.save(%{access_token: "saved", expires_at: System.os_time(:second) + 3600})
      config = %Config{bot_user: "differentbot", channels: ["channel"]}

      output =
        ExUnit.CaptureIO.capture_io(fn ->
          assert {:error, "missing Twitch OAuth tokens; run oauth.bootstrap"} =
                   TwitchConfig.from_config(config, &valid_token_response/2)
        end)

      assert output =~ "authorized as mybot, but the bot username is differentbot"
      assert :error = TF2Client.Twitch.FileTokenStore.load()
    after
      restore_tokens_path(previous_path)
    end
  end

  @tag :tmp_dir
  test "valid saved credentials connect without browser authorization", %{tmp_dir: tmp_dir} do
    previous_path = System.get_env("TF_TOKENS_PATH")
    System.put_env("TF_TOKENS_PATH", Path.join(tmp_dir, "tokens.json"))

    try do
      :ok = TF2Client.Twitch.FileTokenStore.save(%{access_token: "saved", expires_at: System.os_time(:second) + 3600})
      config = %Config{bot_user: "mybot", channels: ["channel"]}

      output =
        ExUnit.CaptureIO.capture_io(fn ->
          assert {:ok, options} = TwitchConfig.from_config(config, &valid_token_response/2)
          assert options[:pass] == "oauth:saved"
        end)

      assert output == ""
      assert {:ok, %{access_token: "saved"}} = TF2Client.Twitch.FileTokenStore.load()
    after
      restore_tokens_path(previous_path)
    end
  end

  defp valid_token_response(_request, _finch) do
    {:ok, %Finch.Response{status: 200, body: Jason.encode!(%{login: "mybot", scopes: ["chat:read", "chat:edit"]})}}
  end

  defp restore_tokens_path(nil), do: System.delete_env("TF_TOKENS_PATH")
  defp restore_tokens_path(path), do: System.put_env("TF_TOKENS_PATH", path)
end
