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

  test "parses enable/disable commands" do
    assert {:ok, {:tf2_on}} = Commands.parse("!tf2on")
    assert {:ok, {:tf2_off}} = Commands.parse("!tf2off")
  end

  test "parses pause and resume commands" do
    assert {:ok, {:pause, :town}} = Commands.parse("!pause town")
    assert {:ok, {:resume, :town}} = Commands.parse("!resume town")
    assert {:ok, {:pause, :all}} = Commands.parse("!pause all")
    assert {:ok, {:resume, :all}} = Commands.parse("!resume all")
    assert {:ok, {:paused}} = Commands.parse("!paused")
    assert {:error, _} = Commands.parse("!pause")
    assert {:error, _} = Commands.parse("!resume garbage")
  end

  test "parses claim and town" do
    assert {:ok, {:claim, nil}} = Commands.parse("!claim")
    assert {:ok, {:claim, "My Co"}} = Commands.parse("!claim My Co")
    assert {:ok, {:town, nil}} = Commands.parse("!town")
    assert {:ok, {:town, "Town Co"}} = Commands.parse("!town Town Co")
  end

  test "parses town rename" do
    assert {:ok, {:town_rename, "New Town"}} = Commands.parse("!townname New Town")
    assert {:error, "usage: !townname <name>"} = Commands.parse("!townname")
    assert :town_rename = Commands.pausable_command_name("townname")
  end

  test "parses line and vehicle" do
    assert {:ok, {:line, "road", "stone"}} = Commands.parse("!line road stone")
    assert {:ok, {:vehicle, "rail", "passengers"}} = Commands.parse("!vehicle RAIL passengers")
    assert {:ok, {:vehicle, "rail", "passengers"}} = Commands.parse("!vehicle RAIL passenger")
    assert {:ok, {:vehicle, "road", "iron_ore"}} = Commands.parse("!vehicle ROAD Iron_Ore")
  end

  test "validates carriers" do
    assert {:error, _} = Commands.parse("!line space stone")
  end

  test "validates cargo" do
    assert {:error, "invalid cargo non_existent" <> _} =
             Commands.parse("!vehicle road non_existent")
  end
end
