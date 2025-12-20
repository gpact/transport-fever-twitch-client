defmodule TF2Client.Requests do
  @moduledoc false

  @available_command_examples TF2Client.Commands.examples()

  @carrier_types Enum.map(TF2Client.Game.carrier_types(), &to_string/1)

  @cargo_types Enum.map(TF2Client.Game.cargo_types(), &to_string/1)

  require Logger

  alias TF2Client.GameBridge
  alias TF2Client.GameState
  alias TF2Client.RateLimiter
  alias TF2Client.RequestQueue
  alias TF2Client.RequestTracker

  @purchase_rate_rule %{
    cooldown_seconds: 5 * 60,
    window_seconds: 60 * 60,
    max_in_window: 3
  }

  @stats_cooldown_rule %{cooldown_seconds: 60}

  def handle_chat_command({:help}, _sender, _chat) do
    {:reply, "Commands: #{Enum.join(@available_command_examples, " • ")}"}
  end

  def handle_chat_command({:carriers}, _sender, _chat) do
    {:reply, "Carrier types: #{Enum.join(@carrier_types, ", ")}"}
  end

  def handle_chat_command({:cargo}, _sender, _chat) do
    {:reply, "Cargo types: #{Enum.join(@cargo_types, ", ")}"}
  end

  def handle_chat_command({:profit}, sender, _chat) do
    key = {:user, normalize_username(sender), :profit}

    case RateLimiter.check(key, @stats_cooldown_rule) do
      :deny ->
        Logger.info("Rate limit reached: profit user=#{sender}")
        :ignore

      :allow ->
        profit_reply(sender)
    end
  end

  def handle_chat_command({:vehicles_owned}, sender, _chat) do
    key = {:user, normalize_username(sender), :vehicles_owned}

    case RateLimiter.check(key, @stats_cooldown_rule) do
      :deny ->
        Logger.info("Rate limit reached: vehicles_owned user=#{sender}")
        :ignore

      :allow ->
        vehicles_owned_reply(sender)
    end
  end

  def handle_chat_command({:profit_rankings}, sender, _chat) do
    key = {:global, :profit_rankings}

    case RateLimiter.check(key, @stats_cooldown_rule) do
      :deny ->
        Logger.info("Rate limit reached: profit_rankings requested_by=#{sender}")
        :ignore

      :allow ->
        profit_rankings_reply(sender)
    end
  end

  def handle_chat_command({:claim, company_name}, sender, chat) do
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

  def handle_chat_command({:town, company_name}, sender, chat) do
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

  def handle_chat_command({:line, carrier, cargo}, sender, chat) do
    key = {:user, normalize_username(sender), :purchase_line}

    case RateLimiter.check(key, @purchase_rate_rule) do
      :deny ->
        Logger.info("Rate limit reached: purchase_line user=#{sender}")
        :ignore

      :allow ->
        submit("LINE", sender, chat, %{carrier: carrier, cargo: cargo})
    end
  end

  def handle_chat_command({:vehicle, carrier, cargo}, sender, chat) do
    key = {:user, normalize_username(sender), :purchase_vehicle}

    case RateLimiter.check(key, @purchase_rate_rule) do
      :deny ->
        Logger.info("Rate limit reached: purchase_vehicle user=#{sender}")
        :ignore

      :allow ->
        submit("VEHICLE", sender, chat, %{carrier: carrier, cargo: cargo})
    end
  end

  def handle_chat_command(_other, _sender, _chat), do: :ignore

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
         "@#{sender} I can't reach the game right now. Start Transport Fever 2 with the integration enabled and load a save, then try again."}

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
         "@#{sender} I can't reach the game right now. Start Transport Fever 2 with the integration enabled and load a save, then try again."}

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
         "@#{sender} I can't reach the game right now. Start Transport Fever 2 with the integration enabled and load a save, then try again."}

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
        case RequestQueue.enqueue(type, sender, chat, params, save_uuid) do
          {:ok, order_id} ->
            RequestTracker.track(order_id, %{
              channel: chat,
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
         "@#{sender} I can't reach the game right now. Start Transport Fever 2 with the integration enabled and load a save, then try again."}

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

  defp normalize_params(params) when is_map(params) do
    params
    |> Enum.reject(fn {_k, v} -> is_nil(v) or v == "" end)
    |> Map.new()
  end

  defp action_description("COMPANY", %{company_name: name}) when is_binary(name) and name != "" do
    ~s(claim/create your company "#{name}")
  end

  defp action_description("COMPANY", _params), do: "claim/create your company"

  defp action_description("TOWN", %{company_name: name}) when is_binary(name) and name != "" do
    ~s(get you a town "#{name}")
  end

  defp action_description("TOWN", _params), do: "get you a town"

  defp action_description("LINE", %{carrier: carrier, cargo: cargo})
       when is_binary(carrier) and carrier != "" and is_binary(cargo) and cargo != "" do
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
