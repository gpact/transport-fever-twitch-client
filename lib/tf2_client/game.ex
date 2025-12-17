defmodule TF2Client.Game do
  @carrier_types ~w[road rail air tram water]a

  @cargo_types ~w[food planks logs machines fuel stone grain plastic tools goods
                  crude construction_materials steel oil iron_ore passengers coal]a

  def carrier_types, do: @carrier_types

  def cargo_types, do: @cargo_types
end
