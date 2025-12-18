defmodule TF2Client.Commands do
  @moduledoc false

  @command_flag "!"

  @valid_carriers Enum.map(TF2Client.Game.carrier_types(), &String.upcase(to_string(&1)))

  def examples do
    [
      "!claim [company name]",
      "!town [name]",
      "!line <carrier> <cargo>",
      "!vehicle <carrier> <cargo>",
      "!carriers",
      "!cargo",
      "!profit",
      "!vehicles",
      "!rank",
      "!tf2on",
      "!tf2off"
    ]
  end

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

      [value] when value in ["tf2on"] ->
        {:ok, {:tf2_on}}

      [value] when value in ["tf2off"] ->
        {:ok, {:tf2_off}}

      ["claim"] ->
        {:ok, {:claim, nil}}

      ["claim", name] ->
        {:ok, {:claim, String.trim(name)}}

      ["town"] ->
        {:ok, {:town, nil}}

      ["town", name] ->
        {:ok, {:town, String.trim(name)}}

      ["line", rest] ->
        parse_carrier_cargo(:line, rest)

      ["vehicle", rest] ->
        parse_carrier_cargo(:vehicle, rest)

      [unknown | _] ->
        {:error, "unknown command #{@command_flag}#{unknown}. Try !help"}
    end
  end

  defp parse_carrier_cargo(kind, rest) do
    case String.split(rest, ~r/\s+/, parts: 2, trim: true) do
      [carrier, cargo] ->
        carrier = carrier |> String.trim() |> String.upcase()
        cargo = cargo |> String.trim() |> String.upcase() |> normalize_cargo()

        if carrier in @valid_carriers do
          {:ok, {kind, carrier, cargo}}
        else
          {:error, "invalid carrier #{carrier}. Use: #{Enum.join(@valid_carriers, ", ")}"}
        end

      _ ->
        usage =
          case kind do
            :line -> "!line <carrier> <cargo>"
            :vehicle -> "!vehicle <carrier> <cargo>"
          end

        {:error, "usage: #{usage}"}
    end
  end

  defp normalize_cargo("PASSENGER"), do: "PASSENGERS"
  defp normalize_cargo(cargo), do: cargo
end
