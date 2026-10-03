defmodule TF2Client.Requests do
  @moduledoc false

  @available_command_examples TF2Client.Commands.examples()

  require Logger

  alias TF2Client.GameBridge
  alias TF2Client.GameState
  alias TF2Client.RateLimiter
  alias TF2Client.RequestQueue
  alias TF2Client.RequestTracker
  alias TF2Client.TransportFever

  @purchase_rate_rule %{
    cooldown_seconds: 5 * 60,
    window_seconds: 60 * 60,
    max_in_window: 3
  }

  @stats_cooldown_rule %{cooldown_seconds: 60}

  def handle_chat_command(command, sender, chat) do
    handle_chat_command(command, sender, chat, %{})
  end

  def handle_chat_command({:help}, _sender, _chat, _tags) do
    {:reply, "Commands: #{Enum.join(@available_command_examples, " • ")}"}
  end

  def handle_chat_command({:carriers}, _sender, _chat, _tags) do
    {:reply, "Carrier types: #{Enum.join(TransportFever.carrier_types(), ", ")}"}
  end

  def handle_chat_command({:cargo}, _sender, _chat, _tags) do
    {:reply, "Cargo types: #{Enum.join(TransportFever.cargo_types(), ", ")}"}
  end

  def handle_chat_command({:profit}, sender, _chat, _tags) do
    key = {:user, normalize_username(sender), :profit}

    case check_rate_limit(key, @stats_cooldown_rule, sender, "profit", "!profit", :user) do
      :allow ->
        profit_reply(sender)

      {:reply, reply} ->
        {:reply, reply}
    end
  end

  def handle_chat_command({:vehicles_owned}, sender, _chat, _tags) do
    key = {:user, normalize_username(sender), :vehicles_owned}

    case check_rate_limit(key, @stats_cooldown_rule, sender, "vehicles_owned", "!vehicles", :user) do
      :allow ->
        vehicles_owned_reply(sender)

      {:reply, reply} ->
        {:reply, reply}
    end
  end

  def handle_chat_command({:profit_rankings}, sender, _chat, _tags) do
    key = {:global, :profit_rankings}

    case check_rate_limit(key, @stats_cooldown_rule, sender, "profit_rankings", "!rank", :global) do
      :allow ->
        profit_rankings_reply(sender)

      {:reply, reply} ->
        {:reply, reply}
    end
  end

  def handle_chat_command({:claim, company_name}, sender, chat, _tags) do
    case GameState.read() do
      {:ok, game_state} ->
        if GameState.company_claimed?(game_state, sender) do
          Logger.info("Rate limit reached: claim_once user=#{sender}")
          :ignore
        else
          submit("COMPANY", sender, chat, %{company_name: company_name})
        end

      {:error, _reason} ->
        submit("COMPANY", sender, chat, %{company_name: company_name})
    end
  end

  def handle_chat_command({:town, company_name}, sender, chat, _tags) do
    case GameState.read() do
      {:ok, game_state} ->
        if GameState.town_purchased?(game_state, sender) do
          Logger.info("Rate limit reached: town_once user=#{sender}")
          :ignore
        else
          submit("TOWN", sender, chat, %{company_name: company_name})
        end

      {:error, _reason} ->
        submit("TOWN", sender, chat, %{company_name: company_name})
    end
  end

  def handle_chat_command({:town_rename, town_name}, sender, chat, _tags) do
    case GameState.read() do
      {:ok, game_state} ->
        if GameState.town_purchased?(game_state, sender) do
          submit("TOWN_RENAME", sender, chat, %{town_name: town_name})
        else
          {:reply, "@#{sender} you need to own a town before renaming it."}
        end

      {:error, _reason} ->
        submit("TOWN_RENAME", sender, chat, %{town_name: town_name})
    end
  end

  def handle_chat_command({:line, carrier, cargo}, sender, chat, tags) do
    key = {:user, normalize_username(sender), :purchase_line}

    case check_rate_limit(key, @purchase_rate_rule, sender, "purchase_line", "!line", :user) do
      :allow ->
        submit("LINE", sender, chat, purchase_params(carrier, cargo, tags))

      {:reply, reply} ->
        {:reply, reply}
    end
  end

  def handle_chat_command({:vehicle, carrier, cargo}, sender, chat, tags) do
    key = {:user, normalize_username(sender), :purchase_vehicle}

    case check_rate_limit(key, @purchase_rate_rule, sender, "purchase_vehicle", "!vehicle", :user) do
      :allow ->
        submit("VEHICLE", sender, chat, purchase_params(carrier, cargo, tags))

      {:reply, reply} ->
        {:reply, reply}
    end
  end

  def handle_chat_command({:set_town_creation_enabled, enabled}, sender, chat, _tags)
      when is_boolean(enabled) do
    submit("SET_TOWN_CREATION_ENABLED", sender, chat, %{enabled: enabled})
  end

  def handle_chat_command(_other, _sender, _chat, _tags), do: :ignore

  defp profit_reply(sender) do
    case GameState.read() do
      {:ok, game_state} ->
        case GameState.profit_for_username(game_state, sender) do
          {:ok, profit} when is_integer(profit) and profit >= 0 ->
            {:reply, "@#{sender} your total profit so far is #{format_integer(profit)}."}

          {:ok, profit} when is_integer(profit) ->
            {:reply, "@#{sender} your total profit so far is #{format_integer(profit)} (net loss)."}

          {:error, :profit_unavailable} ->
            {:reply, "@#{sender} I don't have profit data for you yet."}
        end

      {:error, :game_state_missing} ->
        {:reply,
         "@#{sender} I can't reach the game right now. Start Transport Fever with the integration enabled and load a save, then try again."}

      {:error, :game_state_invalid} ->
        {:reply,
         "@#{sender} the game isn't ready yet. Load a save (with the integration enabled) and try again in a few seconds."}

      {:error, {:file_error, reason}} ->
        Logger.warning("Failed to read game state for profit: #{inspect(reason)}")
        {:reply, "@#{sender} I couldn't read the game stats due to a setup issue. Please try again in a moment."}
    end
  end

  defp vehicles_owned_reply(sender) do
    case GameState.read() do
      {:ok, game_state} ->
        case GameState.vehicles_owned_count(game_state, sender) do
          {:ok, 0} ->
            {:reply, "@#{sender} you don't own any vehicles yet."}

          {:ok, 1} ->
            {:reply, "@#{sender} you currently own 1 vehicle."}

          {:ok, count} when is_integer(count) ->
            {:reply, "@#{sender} you currently own #{count} vehicles."}

          {:error, :vehicles_unavailable} ->
            {:reply, "@#{sender} I don't have vehicle data for you yet."}
        end

      {:error, :game_state_missing} ->
        {:reply,
         "@#{sender} I can't reach the game right now. Start Transport Fever with the integration enabled and load a save, then try again."}

      {:error, :game_state_invalid} ->
        {:reply,
         "@#{sender} the game isn't ready yet. Load a save (with the integration enabled) and try again in a few seconds."}

      {:error, {:file_error, reason}} ->
        Logger.warning("Failed to read game state for vehicles owned: #{inspect(reason)}")
        {:reply, "@#{sender} I couldn't read the game stats due to a setup issue. Please try again in a moment."}
    end
  end

  defp profit_rankings_reply(sender) do
    case GameState.read() do
      {:ok, game_state} ->
        rankings = GameState.top_players_by_profit(game_state, 10)

        case rankings do
          [] ->
            {:reply, "@#{sender} I don't have profit data yet."}

          rankings ->
            {:reply, "@#{sender} top profits: " <> format_profit_rankings(rankings)}
        end

      {:error, :game_state_missing} ->
        {:reply,
         "@#{sender} I can't reach the game right now. Start Transport Fever with the integration enabled and load a save, then try again."}

      {:error, :game_state_invalid} ->
        {:reply,
         "@#{sender} the game isn't ready yet. Load a save (with the integration enabled) and try again in a few seconds."}

      {:error, {:file_error, reason}} ->
        Logger.warning("Failed to read game state for profit rankings: #{inspect(reason)}")
        {:reply, "@#{sender} I couldn't read the game stats due to a setup issue. Please try again in a moment."}
    end
  end

  defp submit(type, sender, chat, params) do
    params = normalize_params(params)

    case GameBridge.read_save_uuid() do
      {:ok, save_uuid} ->
        case RequestQueue.submit(type, sender, chat, params, save_uuid) do
          {:ok, order_id} ->
            RequestTracker.track(order_id, %{
              channel: chat,
              save_uuid: save_uuid,
              username: sender,
              type: type
            })

            {:reply, queued_message(type, sender, params)}

          {:error, reason} ->
            Logger.warning("Failed to enqueue request: #{inspect(reason)}")
            {:reply, "@#{sender} something went wrong on my side. Please try again in a moment."}
        end

      {:error, :game_state_missing} ->
        {:reply,
         "@#{sender} I can't reach the game right now. Start Transport Fever with the integration enabled and load a save, then try again."}

      {:error, :save_uuid_missing} ->
        {:reply,
         "@#{sender} the game isn't ready yet. Load a save (with the integration enabled) and try again in a few seconds."}

      {:error, :game_state_invalid} ->
        {:reply,
         "@#{sender} the game isn't ready yet. Load a save (with the integration enabled) and try again in a few seconds."}

      {:error, {:file_error, reason}} ->
        Logger.warning("Failed to read game state for queued request: #{inspect(reason)}")
        {:reply, "@#{sender} I couldn't send that to the game due to a setup issue. Please try again in a moment."}
    end
  end

  defp queued_message(type, sender, params) when is_binary(type) and is_binary(sender) and is_map(params) do
    action = action_description(type, params)
    "@#{sender} got it! I'll try to #{action}."
  end

  defp check_rate_limit(key, rule, sender, log_label, command_name, scope)
       when is_binary(sender) and is_binary(log_label) and is_binary(command_name) do
    case RateLimiter.check_with_retry_after(key, rule) do
      :allow ->
        :allow

      {:deny, retry_after_seconds} ->
        Logger.info("Rate limit reached: #{log_label} user=#{sender}")
        {:reply, rate_limit_reply(sender, command_name, retry_after_seconds, scope)}
    end
  end

  defp rate_limit_reply(sender, command_name, retry_after_seconds, :global) do
    duration = format_cooldown_duration(retry_after_seconds)
    "@#{sender} #{command_name} is on cooldown for everyone for the next #{duration}."
  end

  defp rate_limit_reply(sender, command_name, retry_after_seconds, :user) do
    duration = format_cooldown_duration(retry_after_seconds)
    "@#{sender} #{command_name} is on cooldown for you for the next #{duration}."
  end

  defp format_cooldown_duration(retry_after_seconds) when is_integer(retry_after_seconds) do
    retry_after_seconds
    |> cooldown_minutes()
    |> format_minutes()
  end

  defp format_cooldown_duration(_retry_after_seconds), do: "a while"

  defp cooldown_minutes(seconds) when seconds > 0 do
    div(seconds + 59, 60)
  end

  defp cooldown_minutes(_seconds), do: 1

  defp format_minutes(1), do: "1 minute"
  defp format_minutes(minutes), do: "#{minutes} minutes"

  defp normalize_params(params) when is_map(params) do
    params
    |> Enum.reject(fn {_k, v} -> is_nil(v) or v == "" end)
    |> Map.new()
  end

  defp purchase_params(carrier, cargo, tags) do
    params = %{carrier: carrier, cargo: cargo}

    case twitch_color(tags) do
      nil -> params
      color -> Map.put(params, :color, color)
    end
  end

  defp twitch_color(%{"color" => color}) when is_binary(color) do
    parse_hex_color(color)
  end

  defp twitch_color(_tags), do: nil

  defp parse_hex_color("#" <> hex) when byte_size(hex) == 6 do
    with {:ok, red} <- parse_hex_component(binary_part(hex, 0, 2)),
         {:ok, green} <- parse_hex_component(binary_part(hex, 2, 2)),
         {:ok, blue} <- parse_hex_component(binary_part(hex, 4, 2)) do
      %{
        red: normalize_color_component(red),
        green: normalize_color_component(green),
        blue: normalize_color_component(blue)
      }
    else
      :error -> nil
    end
  end

  defp parse_hex_color(_color), do: nil

  defp parse_hex_component(hex) when is_binary(hex) do
    case Integer.parse(hex, 16) do
      {value, ""} when value >= 0 and value <= 255 -> {:ok, value}
      _other -> :error
    end
  end

  defp normalize_color_component(value) when is_integer(value) do
    value / 255
  end

  defp action_description("COMPANY", %{company_name: name}) when is_binary(name) and name != "" do
    ~s(claim/create your company "#{name}")
  end

  defp action_description("COMPANY", _params), do: "claim/create your company"

  defp action_description("TOWN", %{company_name: name}) when is_binary(name) and name != "" do
    ~s(get you a town "#{name}")
  end

  defp action_description("TOWN", _params), do: "get you a town"

  defp action_description("TOWN_RENAME", %{town_name: <<_, _::binary>> = name}) do
    ~s(rename your town to "#{name}")
  end

  defp action_description("LINE", %{carrier: <<_, _::binary>> = carrier, cargo: <<_, _::binary>> = cargo}) do
    carrier = String.downcase(carrier)
    cargo = String.downcase(cargo)
    "set up a #{carrier} line for #{cargo}"
  end

  defp action_description("LINE", _params), do: "set up a transport line"

  defp action_description("VEHICLE", %{carrier: carrier, cargo: cargo})
       when is_binary(carrier) and carrier != "" and is_binary(cargo) and cargo != "" do
    carrier = String.downcase(carrier)
    cargo = String.downcase(cargo)
    "add a #{carrier} vehicle for #{cargo}"
  end

  defp action_description("VEHICLE", _params), do: "add a vehicle"

  defp action_description("SET_TOWN_CREATION_ENABLED", %{enabled: true}) do
    "enable town creation"
  end

  defp action_description("SET_TOWN_CREATION_ENABLED", %{enabled: false}) do
    "disable town creation"
  end

  defp action_description(_type, _params), do: "do that"

  defp format_integer(value) when is_integer(value) do
    sign = if value < 0, do: "-", else: ""
    digits = Integer.to_string(abs(value))

    chunks =
      digits
      |> String.reverse()
      |> String.graphemes()
      |> Enum.chunk_every(3)
      |> Enum.map(&Enum.join/1)
      |> Enum.join(",")
      |> String.reverse()

    sign <> chunks
  end

  defp format_profit_rankings(rankings) when is_list(rankings) do
    rankings
    |> Enum.with_index(1)
    |> Enum.map(fn {{username, profit}, index} ->
      "#{index}) #{username}: #{format_integer(profit)}"
    end)
    |> Enum.join(" • ")
  end

  defp normalize_username(username) when is_binary(username) do
    String.downcase(String.trim(username))
  end
end
