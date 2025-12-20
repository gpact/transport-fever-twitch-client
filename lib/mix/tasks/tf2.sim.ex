defmodule Mix.Tasks.Tf2.Sim do
  @shortdoc "Interactive local simulator for TF2Client chat commands"

  use Mix.Task

  alias TF2Client.Chat
  alias TF2Client.Commands
  alias TF2Client.GameBridge
  alias TF2Client.RequestTracker
  alias TF2Client.Requests
  alias TF2Client.ResponsePoller
  alias TF2Client.Sim.Mod

  @default_script_delay_ms 250

  @impl Mix.Task
  def run(_args) do
    Application.ensure_all_started(:logger)
    Application.put_env(:tf2_client, :chat_sender, TF2Client.Chat.IO)

    ensure_requests_env()
    ensure_requests_dir()
    ensure_game_state()

    {:ok, _} = start_children()

    IO.puts("TF2Client sim started.")
    IO.puts("Requests dir: #{GameBridge.requests_dir()}")
    IO.puts("Type :help for simulator commands. Type chat like: alice: !claim My Co")

    loop(%{default_sender: "tester", channel: "streamer", auto: true, last_order_id: nil})
  end

  defp start_children do
    children = [
      RequestTracker,
      ResponsePoller
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end

  defp loop(state) do
    line = IO.gets("> ")

    case line do
      nil ->
        :ok

      line ->
        state =
          line
          |> String.trim_trailing()
          |> handle_line(state)

        loop(state)
    end
  end

  defp handle_line("", state), do: state

  defp handle_line(":" <> rest, state) do
    handle_sim_command(String.trim(rest), state)
  end

  defp handle_line(line, state) do
    {sender, message} = split_sender(line, state.default_sender)

    case Commands.parse(message) do
      :ignore ->
        state

      {:error, error} ->
        Chat.send(state.channel, "@#{sender} #{error}")
        state

      {:ok, command} ->
        before = MapSet.new(RequestTracker.pending_ids())
        result = Requests.handle_chat_command(command, sender, state.channel)
        after_ids = MapSet.new(RequestTracker.pending_ids())
        new_ids = MapSet.difference(after_ids, before) |> MapSet.to_list()

        case result do
          {:reply, reply} when is_binary(reply) ->
            Chat.send(state.channel, reply)

          :ignore ->
            :ok
        end

        order_id = Enum.at(new_ids, 0)

        state =
          if is_binary(order_id) do
            state = %{state | last_order_id: order_id}

            if state.auto do
              tracked = RequestTracker.get(order_id) || %{}
              username = tracked[:username] || sender
              type = tracked[:type] || extract_type_from_reply(result) || "UNKNOWN"
              auto_complete(order_id, username, type)
            end

            state
          else
            state
          end

        state
    end
  end

  defp handle_sim_command("help", state) do
    IO.puts("""
    Simulator commands:
      :help                 show this help
      :dir                  print requests dir
      :auto on|off           toggle auto responses (default: on)
      :sender <name>         set default sender (default: tester)
      :channel <name>        set channel label used in output (default: streamer)
      :save <save_uuid>      write gameState.json save_uuid
      :play <path> [delay]   play script file; delay in ms (default: #{@default_script_delay_ms})
      :respond <id|last> ok
      :respond <id|last> pending
      :respond <id|last> error <message>
      :quit
    """)

    state
  end

  defp handle_sim_command("quit", state) do
    System.halt(0)
    state
  end

  defp handle_sim_command("dir", state) do
    IO.puts(GameBridge.requests_dir())
    state
  end

  defp handle_sim_command("auto on", state), do: %{state | auto: true}
  defp handle_sim_command("auto off", state), do: %{state | auto: false}

  defp handle_sim_command("play " <> rest, state) do
    rest = String.trim(rest)

    case parse_play_args(rest) do
      {:ok, path, delay_ms} ->
        play_script_file(path, delay_ms, state)

      {:error, message} ->
        IO.puts(message)
        state
    end
  end

  defp handle_sim_command("sender " <> sender, state) do
    %{state | default_sender: String.trim(sender)}
  end

  defp handle_sim_command("channel " <> channel, state) do
    %{state | channel: String.trim(channel)}
  end

  defp handle_sim_command("save " <> save_uuid, state) do
    save_uuid = String.trim(save_uuid)
    File.write!(GameBridge.game_state_path(), ~s({"save_uuid":"#{save_uuid}"}\n))
    IO.puts("Wrote save_uuid=#{save_uuid} to #{GameBridge.game_state_path()}")
    state
  end

  defp handle_sim_command("respond " <> rest, state) do
    parts = String.split(rest, ~r/\s+/, trim: true)

    with [id_or_last, status | tail] <- parts,
         order_id <- if(id_or_last == "last", do: state.last_order_id, else: id_or_last),
         true <- is_binary(order_id) and order_id != "" do
      tracked = RequestTracker.get(order_id) || %{}
      username = tracked[:username] || state.default_sender
      type = tracked[:type] || "UNKNOWN"

      case {status, tail} do
        {"ok", _} ->
          Mod.write_response(order_id, username, type, :ok)

        {"pending", _} ->
          Mod.write_response(order_id, username, type, :pending)

        {"error", msg_parts} ->
          Mod.write_response(order_id, username, type, :error, Enum.join(msg_parts, " "))

        _ ->
          IO.puts("Usage: :respond <id|last> ok|pending|error <message>")
      end
    else
      _ ->
        IO.puts("Usage: :respond <id|last> ok|pending|error <message>")
    end

    state
  end

  defp handle_sim_command(_unknown, state) do
    IO.puts("Unknown simulator command. Type :help")
    state
  end

  @doc false
  def simulate_lines(lines, state, delay_ms \\ @default_script_delay_ms) when is_list(lines) do
    Enum.reduce(lines, state, fn line, state ->
      state = handle_line(line, state)
      maybe_sleep(delay_ms)
      state
    end)
  end

  defp split_sender(line, default_sender) do
    cond do
      String.contains?(line, ":") ->
        case String.split(line, ":", parts: 2) do
          [sender, msg] -> {String.trim(sender), String.trim_leading(msg)}
          _ -> {default_sender, line}
        end

      String.contains?(line, ">") ->
        case String.split(line, ">", parts: 2) do
          [sender, msg] -> {String.trim(sender), String.trim_leading(msg)}
          _ -> {default_sender, line}
        end

      true ->
        {default_sender, line}
    end
  end

  defp auto_complete(order_id, sender, type) do
    Task.start(fn ->
      Process.sleep(300)
      Mod.write_response(order_id, sender, type, :ok)
    end)
  end

  defp extract_type_from_reply({:reply, reply}) when is_binary(reply) do
    case Regex.run(~r/queued\s+([A-Z_]+)\s+request/, reply) do
      [_, type] -> type
      _ -> nil
    end
  end

  defp extract_type_from_reply(_), do: nil

  defp ensure_requests_dir do
    File.mkdir_p!(GameBridge.requests_dir())
  end

  defp ensure_requests_env do
    if System.get_env("TF2_INTEGRATION_GAME_FILES") do
      :ok
    else
      dir =
        Path.join(System.tmp_dir!(), "tf2-sim-" <> Base.encode16(:crypto.strong_rand_bytes(4), case: :lower))

      System.put_env("TF2_INTEGRATION_GAME_FILES", dir)
      :ok
    end
  end

  defp ensure_game_state do
    path = GameBridge.game_state_path()

    if not File.exists?(path) do
      File.write!(path, ~s({"save_uuid":"sim-save"}\n))
    end
  end

  defp parse_play_args(""), do: {:error, "Usage: :play <path> [delay_ms]"}

  defp parse_play_args(rest) do
    case String.split(rest, ~r/\s+/, parts: 2, trim: true) do
      [path] ->
        {:ok, path, @default_script_delay_ms}

      [path, delay_raw] ->
        delay_raw = String.trim(delay_raw)

        case Integer.parse(delay_raw) do
          {delay_ms, ""} when delay_ms >= 0 ->
            {:ok, path, delay_ms}

          _ ->
            {:error, "Usage: :play <path> [delay_ms]"}
        end

      _ ->
        {:error, "Usage: :play <path> [delay_ms]"}
    end
  end

  defp play_script_file(path, delay_ms, state) do
    case File.read(path) do
      {:ok, contents} ->
        lines = script_lines(contents)
        simulate_lines(lines, state, delay_ms)

      {:error, reason} ->
        IO.puts("Failed to read script file: #{inspect(reason)}")
        state
    end
  end

  defp script_lines(contents) when is_binary(contents) do
    contents
    |> String.split(~r/\R/, trim: false)
    |> Enum.map(&String.trim_trailing/1)
    |> Enum.reject(&script_skip_line?/1)
  end

  defp script_skip_line?(line) when is_binary(line) do
    trimmed = String.trim(line)
    trimmed == "" or String.starts_with?(trimmed, "#")
  end

  defp maybe_sleep(delay_ms) when is_integer(delay_ms) and delay_ms > 0 do
    Process.sleep(delay_ms)
  end

  defp maybe_sleep(_delay_ms), do: :ok
end
