defmodule TF2Client.TransportFever.TF3 do
  @moduledoc false

  @behaviour TF2Client.TransportFever.Version

  @carriers ~w[road rail tram water air]

  @cargo_classes ~w[bulk flatbed goods liquid passengers universal]

  @cargo_by_class %{
    goods: ~w[
      beverages books bricks canned_food clothes fabric fish furniture
      glass meat paper plastic tires tools vegetables wool
    ],
    bulk: ~w[
      cement clay coal fertilizer grain iron_ore sand sawdust stone
    ],
    flatbed: ~w[
      logs machines planks sheet_metal steel vehicles
    ],
    liquid: ~w[
      chemicals crude_oil dyes fuel rubber
    ],
    passengers: ~w[
      passengers
    ]
  }

  @cargo_types Enum.flat_map(@cargo_by_class, fn {_class, types} -> types end)

  @cargo_to_class for {class, types} <- @cargo_by_class,
                      type <- types,
                      into: %{},
                      do: {type, to_string(class)}

  @cargo_aliases %{
    "passenger" => "passengers",
    "tinned_food" => "canned_food"
  }

  @carrier_aliases %{
    "ship" => "water",
    "boat" => "water",
    "plane" => "air",
    "flight" => "air",
    "train" => "rail",
    "bus" => "road",
    "truck" => "road"
  }

  @impl true
  def version, do: :tf3

  @impl true
  def carrier_types, do: @carriers

  @impl true
  def cargo_types, do: @cargo_types

  @impl true
  def cargo_classes, do: @cargo_classes

  @impl true
  def normalize_carrier(carrier) when is_binary(carrier) do
    normalized =
      carrier
      |> String.trim()
      |> String.downcase()
      |> String.replace(~r/[\s-]+/, "_")

    resolved = Map.get(@carrier_aliases, normalized, normalized)

    case resolved in @carriers do
      true -> {:ok, resolved}
      false -> {:error, :invalid_carrier}
    end
  end

  def normalize_carrier(_carrier), do: {:error, :invalid_carrier}

  @impl true
  def normalize_cargo(cargo) when is_binary(cargo) do
    normalized =
      cargo
      |> String.trim()
      |> String.downcase()
      |> String.replace(~r/[\s-]+/, "_")

    resolved = Map.get(@cargo_aliases, normalized, normalized)

    case resolved in @cargo_types do
      true -> {:ok, resolved}
      false -> {:error, :invalid_cargo}
    end
  end

  def normalize_cargo(_cargo), do: {:error, :invalid_cargo}

  @impl true
  def valid_carrier?(carrier) when is_binary(carrier) do
    case normalize_carrier(carrier) do
      {:ok, _carrier} -> true
      {:error, _reason} -> false
    end
  end

  def valid_carrier?(_carrier), do: false

  @impl true
  def valid_cargo?(cargo) when is_binary(cargo) do
    case normalize_cargo(cargo) do
      {:ok, _cargo} -> true
      {:error, _reason} -> false
    end
  end

  def valid_cargo?(_cargo), do: false

  @impl true
  def cargo_class(cargo) when is_binary(cargo) do
    case normalize_cargo(cargo) do
      {:ok, resolved} -> Map.get(@cargo_to_class, resolved)
      {:error, _reason} -> nil
    end
  end

  def cargo_class(_cargo), do: nil

  @impl true
  def wire_carrier(carrier) when is_binary(carrier), do: carrier

  @impl true
  def wire_cargo("canned_food"), do: "tinned_food"
  def wire_cargo(cargo) when is_binary(cargo), do: cargo
end
