defmodule TF2Client.Game do
  @moduledoc false

  alias TF2Client.TransportFever

  def carrier_types do
    Enum.map(TransportFever.carrier_types(), &String.to_atom/1)
  end

  def cargo_types do
    Enum.map(TransportFever.cargo_types(), &String.to_atom/1)
  end
end
