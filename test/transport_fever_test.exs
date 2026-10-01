defmodule TF2Client.TransportFeverTest do
  use ExUnit.Case, async: false

  alias TF2Client.TransportFever
  alias TF2Client.TransportFever.TF2
  alias TF2Client.TransportFever.TF3

  setup do
    previous_version = Application.get_env(:tf2_client, :transport_fever_version)

    on_exit(fn ->
      case previous_version do
        nil -> Application.delete_env(:tf2_client, :transport_fever_version)
        val -> Application.put_env(:tf2_client, :transport_fever_version, val)
      end
    end)

    :ok
  end

  describe "configuration and facade" do
    test "defaults to tf3 when unconfigured" do
      Application.delete_env(:tf2_client, :transport_fever_version)
      assert TransportFever.version() == :tf3
      assert TransportFever.implementation() == TF3
    end

    test "selects tf2 when configured" do
      Application.put_env(:tf2_client, :transport_fever_version, :tf2)
      assert TransportFever.version() == :tf2
      assert TransportFever.implementation() == TF2
    end

    test "selects tf3 when explicitly configured" do
      Application.put_env(:tf2_client, :transport_fever_version, :tf3)
      assert TransportFever.version() == :tf3
      assert TransportFever.implementation() == TF3
    end

    test "parses string versions case-insensitively" do
      assert TransportFever.parse_version("tf2") == :tf2
      assert TransportFever.parse_version("TF2") == :tf2
      assert TransportFever.parse_version("tf3") == :tf3
      assert TransportFever.parse_version("TF3") == :tf3
    end

    test "raises clearly on unsupported version" do
      assert_raise RuntimeError, ~r/Unsupported TRANSPORT_FEVER_VERSION="tf4"/, fn ->
        TransportFever.parse_version("tf4")
      end

      assert_raise RuntimeError, ~r/Unsupported TRANSPORT_FEVER_VERSION=:invalid/, fn ->
        TransportFever.parse_version(:invalid)
      end
    end
  end

  describe "TF3 carriers" do
    test "normalizes supported carriers" do
      assert TF3.normalize_carrier("road") == {:ok, "road"}
      assert TF3.normalize_carrier("rail") == {:ok, "rail"}
      assert TF3.normalize_carrier("tram") == {:ok, "tram"}
      assert TF3.normalize_carrier("water") == {:ok, "water"}
      assert TF3.normalize_carrier("air") == {:ok, "air"}
    end

    test "normalizes carrier aliases" do
      assert TF3.normalize_carrier("ship") == {:ok, "water"}
      assert TF3.normalize_carrier("boat") == {:ok, "water"}
      assert TF3.normalize_carrier("train") == {:ok, "rail"}
      assert TF3.normalize_carrier("bus") == {:ok, "road"}
      assert TF3.normalize_carrier("truck") == {:ok, "road"}
      assert TF3.normalize_carrier("plane") == {:ok, "air"}
      assert TF3.normalize_carrier("flight") == {:ok, "air"}
    end

    test "handles case and whitespace in carriers" do
      assert TF3.normalize_carrier("  ROAD  ") == {:ok, "road"}
      assert TF3.normalize_carrier("Rail") == {:ok, "rail"}
      assert TF3.normalize_carrier("TrAm") == {:ok, "tram"}
    end

    test "rejects invalid carriers" do
      assert TF3.normalize_carrier("spaceship") == {:error, :invalid_carrier}
      assert TF3.normalize_carrier("hovercraft") == {:error, :invalid_carrier}
      assert TF3.normalize_carrier(nil) == {:error, :invalid_carrier}
      assert TF3.valid_carrier?("spaceship") == false
    end
  end

  describe "TF3 cargo" do
    test "normalizes goods category cargo" do
      assert TF3.normalize_cargo("books") == {:ok, "books"}
      assert TF3.normalize_cargo("beverages") == {:ok, "beverages"}
      assert TF3.normalize_cargo("tools") == {:ok, "tools"}
      assert TF3.normalize_cargo("wool") == {:ok, "wool"}
      assert TF3.cargo_class("books") == "goods"
    end

    test "normalizes bulk category cargo" do
      assert TF3.normalize_cargo("cement") == {:ok, "cement"}
      assert TF3.normalize_cargo("coal") == {:ok, "coal"}
      assert TF3.normalize_cargo("grain") == {:ok, "grain"}
      assert TF3.normalize_cargo("stone") == {:ok, "stone"}
      assert TF3.cargo_class("coal") == "bulk"
    end

    test "normalizes flatbed category cargo" do
      assert TF3.normalize_cargo("logs") == {:ok, "logs"}
      assert TF3.normalize_cargo("machines") == {:ok, "machines"}
      assert TF3.normalize_cargo("planks") == {:ok, "planks"}
      assert TF3.normalize_cargo("steel") == {:ok, "steel"}
      assert TF3.cargo_class("steel") == "flatbed"
    end

    test "normalizes liquid category cargo" do
      assert TF3.normalize_cargo("chemicals") == {:ok, "chemicals"}
      assert TF3.normalize_cargo("fuel") == {:ok, "fuel"}
      assert TF3.normalize_cargo("rubber") == {:ok, "rubber"}
      assert TF3.cargo_class("fuel") == "liquid"
    end

    test "normalizes passengers" do
      assert TF3.normalize_cargo("passengers") == {:ok, "passengers"}
      assert TF3.normalize_cargo("passenger") == {:ok, "passengers"}
      assert TF3.cargo_class("passengers") == "passengers"
    end

    test "normalizes multi-word cargo with spaces and hyphens" do
      assert TF3.normalize_cargo("iron ore") == {:ok, "iron_ore"}
      assert TF3.normalize_cargo("iron-ore") == {:ok, "iron_ore"}
      assert TF3.normalize_cargo("IRON ORE") == {:ok, "iron_ore"}
      assert TF3.normalize_cargo("Iron Ore") == {:ok, "iron_ore"}

      assert TF3.normalize_cargo("crude oil") == {:ok, "crude_oil"}
      assert TF3.normalize_cargo("crude-oil") == {:ok, "crude_oil"}

      assert TF3.normalize_cargo("sheet metal") == {:ok, "sheet_metal"}
      assert TF3.normalize_cargo("sheet-metal") == {:ok, "sheet_metal"}
    end

    test "normalizes canned food and translates wire representation" do
      assert TF3.normalize_cargo("canned_food") == {:ok, "canned_food"}
      assert TF3.normalize_cargo("canned food") == {:ok, "canned_food"}
      assert TF3.normalize_cargo("tinned_food") == {:ok, "canned_food"}
      assert TF3.normalize_cargo("tinned food") == {:ok, "canned_food"}

      assert TF3.wire_cargo("canned_food") == "tinned_food"
      assert TF3.wire_cargo("iron_ore") == "iron_ore"
    end

    test "rejects invalid cargo" do
      assert TF3.normalize_cargo("spaceship") == {:error, :invalid_cargo}
      assert TF3.normalize_cargo("bananas") == {:error, :invalid_cargo}
      assert TF3.normalize_cargo("uranium") == {:error, :invalid_cargo}
      assert TF3.valid_cargo?("bananas") == false
    end
  end

  describe "TF2 compatibility implementation" do
    test "exposes TF2 carrier and cargo types" do
      assert TF2.carrier_types() == ["road", "rail", "air", "tram", "water"]
      assert "food" in TF2.cargo_types()
      assert "crude" in TF2.cargo_types()
      assert "construction_materials" in TF2.cargo_types()
      refute "beverages" in TF2.cargo_types()
    end

    test "normalizes TF2 values correctly" do
      assert TF2.normalize_carrier("road") == {:ok, "road"}
      assert TF2.normalize_carrier("ROAD") == {:ok, "road"}
      assert TF2.normalize_cargo("food") == {:ok, "food"}
      assert TF2.normalize_cargo("passenger") == {:ok, "passengers"}
      assert TF2.wire_cargo("food") == "food"
    end
  end
end
