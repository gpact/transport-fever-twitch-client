defmodule TF2Client.Twitch.OAuthBootstrapTest do
  use ExUnit.Case, async: true

  alias TF2Client.Twitch.OAuthBootstrap

  describe "browser_command_for_os/2" do
    test "uses the Windows URL file protocol handler without cmd shell parsing" do
      url = "https://id.twitch.tv/oauth2/authorize?client_id=abc&response_type=code"

      assert OAuthBootstrap.browser_command_for_os(url, {:win32, :nt}) ==
               {"rundll32.exe", ["url.dll,FileProtocolHandler", url]}
    end

    test "uses open on macOS" do
      url = "https://id.twitch.tv/oauth2/authorize?client_id=abc&response_type=code"

      assert OAuthBootstrap.browser_command_for_os(url, {:unix, :darwin}) == {"open", [url]}
    end

    test "uses xdg-open on other Unix platforms" do
      url = "https://id.twitch.tv/oauth2/authorize?client_id=abc&response_type=code"

      assert OAuthBootstrap.browser_command_for_os(url, {:unix, :linux}) == {"xdg-open", [url]}
    end
  end
end
