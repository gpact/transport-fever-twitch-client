defmodule TF2Client.TransportFever.Version do
  @moduledoc false

  @callback version() :: :tf2 | :tf3
  @callback cargo_types() :: [String.t()]
  @callback cargo_classes() :: [String.t()]
  @callback carrier_types() :: [String.t()]
  @callback normalize_cargo(String.t()) :: {:ok, String.t()} | {:error, :invalid_cargo}
  @callback normalize_carrier(String.t()) :: {:ok, String.t()} | {:error, :invalid_carrier}
  @callback valid_cargo?(String.t()) :: boolean()
  @callback valid_carrier?(String.t()) :: boolean()
  @callback cargo_class(String.t()) :: String.t() | nil
  @callback wire_carrier(String.t()) :: String.t()
  @callback wire_cargo(String.t()) :: String.t()
end
