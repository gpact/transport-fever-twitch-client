defmodule TF2Client.Twitch.OAuthBootstrapTest do
  use ExUnit.Case, async: false

  alias TF2Client.Twitch.OAuthBootstrap

  @test_dir Path.join(__DIR__, "../tmp/test_oauth_bootstrap")
  @empty_config Path.join(@test_dir, "config.json")

  setup do
    File.mkdir_p!(@test_dir)
    File.write!(@empty_config, "{}")
    System.put_env("TF2_CONFIG_PATH", @empty_config)

    saved_secret = System.get_env("TWITCH_CLIENT_SECRET")
    System.delete_env("TWITCH_CLIENT_SECRET")

    on_exit(fn ->
      System.delete_env("TF2_CONFIG_PATH")

      case saved_secret do
        nil -> System.delete_env("TWITCH_CLIENT_SECRET")
        val -> System.put_env("TWITCH_CLIENT_SECRET", val)
      end

      File.rm_rf(@test_dir)
    end)

    :ok
  end

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

  describe "authorization_url/0" do
    test "generates token implicit grant URL by default" do
      url = OAuthBootstrap.authorization_url()
      assert String.contains?(url, "response_type=token")
      assert String.contains?(url, "client_id=l4my2fg4doyt5rpr0sow94d441jxxl")
      assert String.contains?(url, "redirect_uri=http%3A%2F%2Flocalhost%3A4000%2Foauth%2Fcallback")
      assert String.contains?(url, "scope=chat%3Aread+chat%3Aedit+channel%3Amoderate")
    end

    test "generates code flow URL when client_secret is set" do
      System.put_env("TWITCH_CLIENT_SECRET", "custom_secret")

      try do
        url = OAuthBootstrap.authorization_url()
        assert String.contains?(url, "response_type=code")
      after
        System.delete_env("TWITCH_CLIENT_SECRET")
      end
    end
  end
end
