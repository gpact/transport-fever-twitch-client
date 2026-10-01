defmodule TF2Client.Commands do
  @moduledoc false

  @command_flag "!"

  @valid_carriers Enum.map(TF2Client.Game.carrier_types(), &to_string/1)
  @valid_cargo Enum.map(TF2Client.Game.cargo_types(), &to_string/1)

  @pausable_commands [:claim, :town, :town_rename, :line, :vehicle]

  @pausable_command_names %{
    "claim" => :claim,
    "town" => :town,
    "townname" => :town_rename,
    "line" => :line,
    "vehicle" => :vehicle
  }

  @pause_target_aliases Map.merge(@pausable_command_names, %{
                          "company" => :claim,
                          "companies" => :claim,
                          "towns" => :town,
                          "lines" => :line,
                          "vehicles" => :vehicle,
                          "all" => :all
                        })

  @admin_commands ["tfon", "tfoff", "pause", "resume", "paused", "towncreation"]

  def examples do
    [
      "!claim [company name]",
      "!town [name]",
      "!townname <name>",
      "!line <carrier> <cargo>",
      "!vehicle <carrier> <cargo>",
      "!carriers",
      "!cargo",
      "!profit",
      "!vehicles",
      "!rank",
      "!tfon",
      "!tfoff",
      "!paused",
      "!pause <claim|town|townname|line|vehicle|all>",
      "!resume <claim|town|townname|line|vehicle|all>",
      "!towncreation <on|off>"
    ]
  end

  def admin_command?(name) when is_binary(name) do
    String.downcase(String.trim(name)) in @admin_commands
  end

  def admin_command?(_), do: false

  def pausable_commands do
    @pausable_commands
  end

  def command_name(message) when is_binary(message) do
    message = String.trim(message)

    case message do
      "" ->
        nil

      _ ->
        case String.starts_with?(message, @command_flag) do
          true -> command_name_from_flagged(message)
          false -> nil
        end
    end
  end

  def pause_target(name) when is_binary(name) do
    name
    |> String.trim()
    |> String.downcase()
    |> then(&Map.get(@pause_target_aliases, &1))
  end

  def pausable_command_name(name) when is_binary(name) do
    name
    |> String.trim()
    |> String.downcase()
    |> then(&Map.get(@pausable_command_names, &1))
  end

  def pausable_command_key({:claim, _}), do: :claim
  def pausable_command_key({:town, _}), do: :town
  def pausable_command_key({:town_rename, _}), do: :town_rename
  def pausable_command_key({:line, _, _}), do: :line
  def pausable_command_key({:vehicle, _, _}), do: :vehicle
  def pausable_command_key(_), do: nil

  def parse(message) when is_binary(message) do
    message = String.trim(message)

    cond do
      message == "" ->
        :ignore

      not String.starts_with?(message, @command_flag) ->
        :ignore

      true ->
        do_parse(String.trim_leading(message, @command_flag))
    end
  end

  defp do_parse(raw) do
    case String.split(raw, ~r/\s+/, parts: 2, trim: true) do
      [] ->
        :ignore

      ["help"] ->
        {:ok, {:help}}

      [value] when value in ["carrier", "carriers"] ->
        {:ok, {:carriers}}

      [value] when value in ["cargo", "cargos"] ->
        {:ok, {:cargo}}

      [value] when value in ["profit", "profits"] ->
        {:ok, {:profit}}

      [value] when value in ["vehicles", "fleet"] ->
        {:ok, {:vehicles_owned}}

      [value] when value in ["rank", "ranks", "leaderboard", "top"] ->
        {:ok, {:profit_rankings}}

      [value] when value in ["tfon"] ->
        {:ok, {:tf_on}}

      [value] when value in ["tfoff"] ->
        {:ok, {:tf_off}}

      ["paused"] ->
        {:ok, {:paused}}

      ["pause"] ->
        {:error, "usage: #{pause_usage(:pause)}"}

      ["pause", target] ->
        parse_pause(:pause, target)

      ["resume"] ->
        {:error, "usage: #{pause_usage(:resume)}"}

      ["resume", target] ->
        parse_pause(:resume, target)

      ["towncreation"] ->
        {:error, "usage: !towncreation <on|off>"}

      ["towncreation", state] ->
        parse_town_creation(state)

      ["claim"] ->
        {:ok, {:claim, nil}}

      ["claim", name] ->
        {:ok, {:claim, String.trim(name)}}

      ["town"] ->
        {:ok, {:town, nil}}

      ["town", name] ->
        {:ok, {:town, String.trim(name)}}

      ["townname"] ->
        {:error, "usage: !townname <name>"}

      ["townname", name] ->
        {:ok, {:town_rename, String.trim(name)}}

      ["line", rest] ->
        parse_carrier_cargo(:line, rest)

      ["vehicle", rest] ->
        parse_carrier_cargo(:vehicle, rest)

      _ ->
        :ignore
    end
  end

  defp parse_carrier_cargo(kind, rest) do
    case String.split(rest, ~r/\s+/, parts: 2, trim: true) do
      [carrier, cargo] ->
        carrier = normalize_game_type(carrier)
        cargo = normalize_cargo(normalize_game_type(cargo))

        validate_carrier_cargo(kind, carrier, cargo)

      _ ->
        usage =
          case kind do
            :line -> "!line <carrier> <cargo>"
            :vehicle -> "!vehicle <carrier> <cargo>"
          end

        {:error, "usage: #{usage}"}
    end
  end

  defp normalize_game_type(value) when is_binary(value) do
    value = String.trim(value)
    String.downcase(value)
  end

  defp normalize_cargo("passenger"), do: "passengers"
  defp normalize_cargo(cargo), do: cargo

  defp validate_carrier_cargo(kind, carrier, cargo) do
    case {carrier in @valid_carriers, cargo in @valid_cargo} do
      {true, true} -> {:ok, {kind, carrier, cargo}}
      {false, _cargo_valid?} -> {:error, invalid_carrier_message(carrier)}
      {true, false} -> {:error, invalid_cargo_message(cargo)}
    end
  end

  defp invalid_carrier_message(carrier) do
    "invalid carrier #{carrier}. Use: #{Enum.join(@valid_carriers, ", ")}"
  end

  defp invalid_cargo_message(cargo) do
    "invalid cargo #{cargo}. Use: #{Enum.join(@valid_cargo, ", ")}"
  end

  defp command_name_from_flagged(message) do
    raw = String.trim_leading(message, @command_flag)

    case String.split(raw, ~r/\s+/, parts: 2, trim: true) do
      [name | _] -> String.downcase(name)
      _ -> nil
    end
  end

  defp parse_pause(action, target) when action in [:pause, :resume] do
    case pause_target(target) do
      nil -> {:error, "usage: #{pause_usage(action)}"}
      pause_target -> {:ok, {action, pause_target}}
    end
  end

  defp pause_usage(:pause), do: "!pause <claim|town|townname|line|vehicle|all>"
  defp pause_usage(:resume), do: "!resume <claim|town|townname|line|vehicle|all>"

  defp parse_town_creation(state) when is_binary(state) do
    case String.downcase(String.trim(state)) do
      val when val in ["on", "true", "enable", "enabled", "1"] ->
        {:ok, {:set_town_creation_enabled, true}}

      val when val in ["off", "false", "disable", "disabled", "0"] ->
        {:ok, {:set_town_creation_enabled, false}}

      _ ->
        {:error, "usage: !towncreation <on|off>"}
    end
  end
end
