defmodule TF2Client.TransportFever do
  @moduledoc """
  Public facade for game-version-specific behavior between Transport Fever 2 and 3.
  """

  alias TF2Client.TransportFever.TF2
  alias TF2Client.TransportFever.TF3

  @default_version :tf3

  def version do
    case Application.get_env(:tf2_client, :transport_fever_version) do
      nil -> env_version()
      configured -> parse_version(configured)
    end
  end

  def implementation do
    case version() do
      :tf2 -> TF2
      :tf3 -> TF3
    end
  end

  def cargo_types, do: implementation().cargo_types()
  def carrier_types, do: implementation().carrier_types()
  def cargo_classes, do: implementation().cargo_classes()

  def normalize_cargo(cargo), do: implementation().normalize_cargo(cargo)
  def normalize_carrier(carrier), do: implementation().normalize_carrier(carrier)

  def valid_cargo?(cargo), do: implementation().valid_cargo?(cargo)
  def valid_carrier?(carrier), do: implementation().valid_carrier?(carrier)

  def cargo_class(cargo), do: implementation().cargo_class(cargo)

  def wire_carrier(carrier), do: implementation().wire_carrier(carrier)
  def wire_cargo(cargo), do: implementation().wire_cargo(cargo)

  def parse_version(:tf2), do: :tf2
  def parse_version(:tf3), do: :tf3

  def parse_version(version) when is_binary(version) do
    case String.downcase(String.trim(version)) do
      "tf2" -> :tf2
      "tf3" -> :tf3
      other -> raise_unsupported_version(other)
    end
  end

  def parse_version(other), do: raise_unsupported_version(other)

  defp env_version do
    case System.get_env("TRANSPORT_FEVER_VERSION") do
      nil -> @default_version
      "" -> @default_version
      value -> parse_version(value)
    end
  end

  defp raise_unsupported_version(value) do
    raise "Unsupported TRANSPORT_FEVER_VERSION=#{inspect(value)}. Supported values: tf2, tf3"
  end
end
