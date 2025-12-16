defmodule TF2Client.Commands do
  @moduledoc false

  @valid_carriers ~w(AIR RAIL ROAD WATER TRAM)

  def parse(message) when is_binary(message) do
    message = String.trim(message)

    cond do
      message == "" ->
        :ignore

      not String.starts_with?(message, "!") ->
        :ignore

      true ->
        do_parse(String.trim_leading(message, "!"))
    end
  end

  defp do_parse(raw) do
    case String.split(raw, ~r/\s+/, parts: 2, trim: true) do
      [] ->
        :ignore

      ["help"] ->
        {:ok, {:help}}

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
        {:error, "unknown command !#{unknown}. Try !help"}
    end
  end

  defp parse_carrier_cargo(kind, rest) do
    case String.split(rest, ~r/\s+/, parts: 2, trim: true) do
      [carrier, cargo] ->
        carrier = carrier |> String.trim() |> String.upcase()
        cargo = cargo |> String.trim() |> String.upcase()

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
end

