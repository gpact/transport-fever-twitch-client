defmodule TF2Client.GameState do
  @moduledoc false

  alias TF2Client.GameBridge

  def company_claimed?(%{} = game_state, username) when is_binary(username) do
    username = String.downcase(username)

    case Map.get(game_state, "companies") do
      %{} = companies ->
        case fetch_case_insensitive(companies, username) do
          {:ok, %{} = _company} -> true
          _ -> false
        end

      _ ->
        false
    end
  end

  def town_purchased?(%{} = game_state, username) when is_binary(username) do
    username = String.downcase(username)

    case Map.get(game_state, "owned_towns") do
      %{} = owned_towns ->
        Enum.any?(owned_towns, fn
          {_town_id, owner} when is_binary(owner) -> String.downcase(owner) == username
          _ -> false
        end)

      _ ->
        false
    end
  end

  def read do
    case File.read(GameBridge.game_state_path()) do
      {:ok, json} ->
        decode_game_state(json)

      {:error, :enoent} ->
        {:error, :game_state_missing}

      {:error, reason} ->
        {:error, {:file_error, reason}}
    end
  end

  def top_players_by_profit(%{} = game_state, limit) when is_integer(limit) and limit > 0 do
    usernames = profit_usernames(game_state)

    profits =
      Enum.reduce(usernames, [], fn username, acc ->
        case profit_for_username(game_state, username) do
          {:ok, profit} when is_integer(profit) -> [{username, profit} | acc]
          _ -> acc
        end
      end)

    sorted = Enum.sort_by(profits, fn {_username, profit} -> profit end, :desc)
    Enum.take(sorted, limit)
  end

  def top_players_by_profit(_game_state, _limit), do: []

  def profit_for_username(%{} = game_state, username) when is_binary(username) do
    username = String.downcase(username)

    case profit_from_players_income(game_state, username) do
      {:ok, profit} ->
        {:ok, profit}

      :not_found ->
        profit_from_companies(game_state, username)
    end
  end

  def vehicles_owned_count(%{} = game_state, username) when is_binary(username) do
    username = String.downcase(username)

    case vehicles_owned_from_owned_vehicles(game_state, username) do
      {:ok, count} ->
        {:ok, count}

      :not_found ->
        vehicles_owned_from_companies(game_state, username)
    end
  end

  defp decode_game_state(json) when is_binary(json) do
    case Jason.decode(json) do
      {:ok, %{} = decoded} -> {:ok, decoded}
      _ -> {:error, :game_state_invalid}
    end
  end

  defp profit_usernames(game_state) when is_map(game_state) do
    usernames = MapSet.new()
    usernames = merge_usernames(usernames, Map.get(game_state, "players_income"))
    usernames = merge_usernames(usernames, Map.get(game_state, "companies"))
    MapSet.to_list(usernames)
  end

  defp merge_usernames(usernames, %{} = map) do
    Enum.reduce(map, usernames, fn
      {username, _value}, usernames when is_binary(username) ->
        MapSet.put(usernames, String.downcase(username))

      _entry, usernames ->
        usernames
    end)
  end

  defp merge_usernames(usernames, _), do: usernames

  defp profit_from_players_income(%{"players_income" => %{} = players_income}, username) do
    case fetch_case_insensitive(players_income, username) do
      {:ok, value} -> normalize_number(value)
      :error -> :not_found
    end
  end

  defp profit_from_players_income(_game_state, _username), do: :not_found

  defp profit_from_companies(%{"companies" => %{} = companies}, username) do
    case fetch_case_insensitive(companies, username) do
      {:ok, %{} = company} -> {:ok, profit_from_company(company)}
      _ -> {:error, :profit_unavailable}
    end
  end

  defp profit_from_companies(_game_state, _username), do: {:error, :profit_unavailable}

  defp profit_from_company(%{} = company) do
    income_total =
      case Map.get(company, "yearlyIncome") do
        %{} = yearly_income -> sum_nested_numbers(yearly_income)
        _ -> 0
      end

    expenses_total =
      case Map.get(company, "yearlyExpenses") do
        %{} = yearly_expenses -> sum_nested_numbers(yearly_expenses)
        _ -> 0
      end

    income_total - expenses_total
  end

  defp vehicles_owned_from_owned_vehicles(%{"owned_vehicles" => %{} = owned_vehicles}, username) do
    count =
      Enum.count(owned_vehicles, fn
        {_vehicle_id, owner} when is_binary(owner) -> String.downcase(owner) == username
        _ -> false
      end)

    {:ok, count}
  end

  defp vehicles_owned_from_owned_vehicles(_game_state, _username), do: :not_found

  defp vehicles_owned_from_companies(%{"companies" => %{} = companies}, username) do
    case fetch_case_insensitive(companies, username) do
      {:ok, %{} = company} ->
        case Map.get(company, "vehicles") do
          %{} = vehicles -> {:ok, map_size(vehicles)}
          _ -> {:ok, 0}
        end

      _ ->
        {:error, :vehicles_unavailable}
    end
  end

  defp vehicles_owned_from_companies(_game_state, _username), do: {:error, :vehicles_unavailable}

  defp sum_nested_numbers(%{} = by_year) do
    Enum.reduce(by_year, 0, fn
      {_year, %{} = entries}, acc -> acc + sum_numbers(entries)
      {_year, _}, acc -> acc
    end)
  end

  defp sum_numbers(%{} = entries) do
    Enum.reduce(entries, 0, fn {_k, v}, acc ->
      acc + number_to_int(v)
    end)
  end

  defp normalize_number(value) when is_integer(value), do: {:ok, value}
  defp normalize_number(value) when is_float(value), do: {:ok, trunc(value)}
  defp normalize_number(_), do: :not_found

  defp number_to_int(value) when is_integer(value), do: value
  defp number_to_int(value) when is_float(value), do: trunc(value)
  defp number_to_int(_), do: 0

  defp fetch_case_insensitive(map, key_downcased) when is_map(map) and is_binary(key_downcased) do
    case Map.fetch(map, key_downcased) do
      {:ok, value} ->
        {:ok, value}

      :error ->
        Enum.find_value(map, :error, fn
          {key, value} when is_binary(key) ->
            if String.downcase(key) == key_downcased do
              {:ok, value}
            else
              false
            end

          _ ->
            false
        end)
    end
  end
end
