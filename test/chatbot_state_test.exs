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
end
