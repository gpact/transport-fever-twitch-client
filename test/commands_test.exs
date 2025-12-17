defmodule TF2Client.CommandsTest do
  use ExUnit.Case, async: true

  alias TF2Client.Commands

  test "ignores non-commands" do
    assert :ignore = Commands.parse("hello")
    assert :ignore = Commands.parse("")
    assert :ignore = Commands.parse("   ")
  end

  test "parses help" do
    assert {:ok, {:help}} = Commands.parse("!help")
  end

  test "parses stats commands" do
    assert {:ok, {:profit}} = Commands.parse("!profit")
    assert {:ok, {:vehicles_owned}} = Commands.parse("!vehicles")
    assert {:ok, {:profit_rankings}} = Commands.parse("!rank")
  end

  test "parses claim and town" do
    assert {:ok, {:claim, nil}} = Commands.parse("!claim")
    assert {:ok, {:claim, "My Co"}} = Commands.parse("!claim My Co")
    assert {:ok, {:town, nil}} = Commands.parse("!town")
    assert {:ok, {:town, "Town Co"}} = Commands.parse("!town Town Co")
  end

  test "parses line and vehicle" do
    assert {:ok, {:line, "ROAD", "STONE"}} = Commands.parse("!line road stone")
    assert {:ok, {:vehicle, "RAIL", "PASSENGERS"}} = Commands.parse("!vehicle RAIL passengers")
    assert {:ok, {:vehicle, "RAIL", "PASSENGERS"}} = Commands.parse("!vehicle RAIL passenger")
  end

  test "validates carriers" do
    assert {:error, _} = Commands.parse("!line space stone")
  end
end
