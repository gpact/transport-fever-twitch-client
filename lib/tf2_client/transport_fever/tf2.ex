defmodule TF2Client.TransportFever.TF2 do
  @moduledoc false

  @behaviour TF2Client.TransportFever.Version

  @carriers ~w[road rail air tram water]
  @cargo_types ~w[
    food planks logs machines fuel stone grain plastic tools goods
    crude construction_materials steel oil iron_ore passengers coal
  ]

  @cargo_aliases %{
    "passenger" => "passengers"
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
  def version, do: :tf2

  @impl true
  def carrier_types, do: @carriers

  @impl true
  def cargo_types, do: @cargo_types

  @impl true
  def cargo_classes, do: []

  @impl true
  def normalize_carrier(carrier) when is_binary(carrier) do
    normalized =
      carrier
      |> String.trim()
      |> String.downcase()

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
  def cargo_class(_cargo), do: nil

  @impl true
  def wire_carrier(carrier) when is_binary(carrier), do: carrier

  @impl true
  def wire_cargo(cargo) when is_binary(cargo), do: cargo
end
