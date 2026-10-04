defmodule TF2Client.Web.ServerTest do
  use ExUnit.Case, async: false

  alias TF2Client.Twitch.FileTokenStore
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
      assert :ok = Server.register_caller(caller)
      assert :ok = Server.deliver_token(%{access_token: "test_server_token", expires_in: 3600})
      assert_receive {:twitch_oauth_token, %{access_token: "test_server_token", expires_in: 3600}}

      # Server remains running after deliveries!
      assert Server.running?() == true

      # Stop server
      assert :ok = Server.stop()
      assert Server.running?() == false
    end
  end

  @tag :tmp_dir
  test "a waiting bootstrap caller owns token persistence and Twitch startup", %{tmp_dir: tmp_dir} do
    previous_path = System.get_env("TF_TOKENS_PATH")
    System.put_env("TF_TOKENS_PATH", Path.join(tmp_dir, "tokens.json"))
    on_exit(fn -> restore_tokens_path(previous_path) end)

    test_process = self()
    start_twitch = fn -> send(test_process, :unexpected_twitch_start) end

    {:ok, _server} = Server.start_link(caller: self(), port: @test_port, ref: @test_ref, start_twitch: start_twitch)

    try do
      token_data = %{access_token: "wrong_account_or_missing_scopes", expires_in: 3600}
      assert :ok = Server.deliver_token(token_data)
      assert_receive {:twitch_oauth_token, ^token_data}
      assert :error = FileTokenStore.load()
      refute_receive :unexpected_twitch_start
      assert Server.running?()
    after
      Server.stop()
    end
  end

  @tag :tmp_dir
  test "startup without a waiting caller can request and receive reauthorization", %{tmp_dir: tmp_dir} do
    previous_path = System.get_env("TF_TOKENS_PATH")
    System.put_env("TF_TOKENS_PATH", Path.join(tmp_dir, "tokens.json"))
    on_exit(fn -> restore_tokens_path(previous_path) end)

    test_process = self()

    start_twitch = fn ->
      assert {:ok, %{access_token: "rejected_token"}} = FileTokenStore.load()
      :ok = FileTokenStore.delete()
      assert :ok = Server.register_caller(self())
      send(test_process, {:reauthorizing, self()})
      assert_receive {:twitch_oauth_token, %{access_token: "replacement_token"}}, 1000
      send(test_process, :reauthorized)
    end

    {:ok, server} = Server.start_link(caller: self(), port: @test_port, ref: @test_ref, start_twitch: start_twitch)

    try do
      assert :ok = Server.deliver_token(%{access_token: "previous_authorization"})
      assert_receive {:twitch_oauth_token, %{access_token: "previous_authorization"}}

      assert :ok = Server.deliver_token(%{access_token: "rejected_token", expires_in: 3600})
      assert_receive {:reauthorizing, worker}, 1000
      refute worker == server
      monitor = Process.monitor(worker)

      assert :ok = Server.deliver_token(%{access_token: "replacement_token", expires_in: 3600})
      assert_receive :reauthorized
      assert_receive {:DOWN, ^monitor, :process, ^worker, :normal}
      assert Server.running?()
    after
      Server.stop()
    end
  end

  test "invalid credentials preserve the waiting caller" do
    {:ok, _server} = Server.start_link(caller: self(), port: @test_port, ref: @test_ref)

    try do
      assert {:error, :invalid_token} = Server.deliver_token(%{access_token: " "})
      assert {:error, :invalid_code} = Server.deliver_code("")
      assert :ok = Server.deliver_token(%{access_token: "valid_token"})
      assert_receive {:twitch_oauth_token, %{access_token: "valid_token"}}
    after
      Server.stop()
    end
  end

  defp restore_tokens_path(nil), do: System.delete_env("TF_TOKENS_PATH")
  defp restore_tokens_path(path), do: System.put_env("TF_TOKENS_PATH", path)
end
