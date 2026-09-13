defmodule TF2Client.Web.ServerTest do
  use ExUnit.Case, async: false

  alias TF2Client.Web.Server

  @test_port 4099
  @test_ref {__MODULE__, :test_http}

  describe "Server lifecycle and caller registration" do
    test "starts and stops on custom port" do
      assert Server.running?() == false

      {:ok, pid} = Server.start_link(port: @test_port, ref: @test_ref)
      assert is_pid(pid)
      assert Server.running?() == true

      caller = self()
      assert :ok = Server.register_caller(caller)

      # Deliver code
      assert :ok = Server.deliver_code("test_server_code")
      assert_receive {:twitch_oauth_code, "test_server_code"}

      # Deliver token
      assert :ok = Server.deliver_token(%{access_token: "test_server_token", expires_in: 3600})
      assert_receive {:twitch_oauth_token, %{access_token: "test_server_token", expires_in: 3600}}

      # Server remains running after deliveries!
      assert Server.running?() == true

      # Stop server
      assert :ok = Server.stop()
      assert Server.running?() == false
    end
  end
end
