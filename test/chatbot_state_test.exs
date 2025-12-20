defmodule TF2Client.ChatbotStateTest do
  use ExUnit.Case, async: false

  alias TF2Client.ChatbotState

  setup do
    ChatbotState.reset()
    :ok
  end

  test "defaults to disabled and toggles per channel" do
    refute ChatbotState.enabled?("somechannel")

    :ok = ChatbotState.enable("somechannel")
    assert ChatbotState.enabled?("somechannel")

    :ok = ChatbotState.disable("somechannel")
    refute ChatbotState.enabled?("somechannel")
  end

  test "normalizes channel name" do
    :ok = ChatbotState.enable("#SomeChannel")
    assert ChatbotState.enabled?("somechannel")
    assert ChatbotState.enabled?("#somechannel")
  end

  test "pauses and resumes commands per channel" do
    refute ChatbotState.paused?("somechannel", :town)

    :ok = ChatbotState.pause("somechannel", :town)
    assert ChatbotState.paused?("somechannel", :town)
    refute ChatbotState.paused?("otherchannel", :town)

    :ok = ChatbotState.resume("somechannel", :town)
    refute ChatbotState.paused?("somechannel", :town)
  end

  test "lists paused commands in sorted order" do
    assert [] == ChatbotState.paused_commands("somechannel")

    :ok = ChatbotState.pause("somechannel", :town)
    :ok = ChatbotState.pause("somechannel", :claim)
    assert [:claim, :town] == ChatbotState.paused_commands("somechannel")
  end
end
