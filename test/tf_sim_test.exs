defmodule TF2Client.TFSimTest do
  use ExUnit.Case, async: false

  alias Mix.Tasks.Tf.Sim, as: TfSim
  alias TF2Client.GameBridge

  setup do
    dir = Path.join(System.tmp_dir!(), "tf-sim-test-" <> Base.encode16(:crypto.strong_rand_bytes(4), case: :lower))
    File.mkdir_p!(dir)

    original_envar = System.get_env("TF_INTEGRATION_GAME_FILES")
    System.put_env("TF_INTEGRATION_GAME_FILES", dir)
    File.write!(Path.join(dir, "gameState.json"), ~s({"save_uuid":"sim-save"}\n))
    initial_rate_limits = Application.get_env(:tf2_client, :disable_rate_limits)

    on_exit(fn ->
      restore_app_env(:disable_rate_limits, initial_rate_limits)
      restore_sys_env("TF_INTEGRATION_GAME_FILES", original_envar)
      File.rm_rf(dir)
    end)

    {:ok, dir: dir}
  end

  test "simulates state changes through commands" do
    Application.put_env(:tf2_client, :disable_rate_limits, true)
    initial_state = %{default_sender: "tester", channel: "streamer", auto: true, last_order_id: nil}

    lines = [
      ":auto off",
      ":ratelimit off",
      ":sender alice",
      ":channel dev_stream"
    ]

    state = TfSim.simulate_lines(lines, initial_state, 0)

    assert state.auto == false
    assert state.default_sender == "alice"
    assert state.channel == "dev_stream"
    assert Application.get_env(:tf2_client, :disable_rate_limits) == true
  end

  test "simulates save uuid updates" do
    initial_state = %{default_sender: "tester", channel: "streamer", auto: true, last_order_id: nil}

    lines = [":save custom-save-uuid"]
    TfSim.simulate_lines(lines, initial_state, 0)

    assert {:ok, "custom-save-uuid"} = GameBridge.read_save_uuid()
  end

  test "tf.sim module is loaded" do
    assert Code.ensure_loaded?(TfSim)
  end

  defp restore_app_env(app \\ :tf2_client, key, value)
  defp restore_app_env(app, key, nil), do: Application.delete_env(app, key)
  defp restore_app_env(app, key, value), do: Application.put_env(app, key, value)

  defp restore_sys_env(key, nil), do: System.delete_env(key)
  defp restore_sys_env(key, value), do: System.put_env(key, value)
end
