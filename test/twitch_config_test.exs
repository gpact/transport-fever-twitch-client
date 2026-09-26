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

    assert {:ok, opts} = TwitchConfig.from_config(config)
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

    assert {:ok, opts} = TwitchConfig.from_config(config)
    assert Keyword.get(opts, :pass) == "oauth:raw_token_without_prefix"
  end
end
