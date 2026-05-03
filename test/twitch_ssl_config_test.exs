defmodule TF2Client.TwitchSSLConfigTest do
  use ExUnit.Case, async: true

  alias TF2Client.TwitchSSLConfig

  test "uses CAStore for Twitch IRC SSL verification" do
    options = TwitchSSLConfig.options("irc.chat.twitch.tv")

    assert Keyword.fetch!(options, :verify) == :verify_peer
    assert Keyword.fetch!(options, :server_name_indication) == ~c"irc.chat.twitch.tv"
    assert File.regular?(Keyword.fetch!(options, :cacertfile))
    assert [match_fun: match_fun] = Keyword.fetch!(options, :customize_hostname_check)
    assert is_function(match_fun, 2)
  end
end
