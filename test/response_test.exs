defmodule TF2Client.ResponseTest do
  use ExUnit.Case, async: true

  alias TF2Client.Response

  test "formats pending responses" do
    json = ~s({"username":"alice","type":"LINE","completed":false,"error":null})
    assert {:ok, parsed} = Response.parse(json)
    assert parsed.completed == false
    assert parsed.error == nil
    assert Response.format(parsed) == "@alice your LINE request is pending"
  end

  test "formats error responses" do
    json = ~s({"username":"bob","type":"TOWN","completed":true,"error":"Unable to assign a town"})
    assert {:ok, parsed} = Response.parse(json)
    assert Response.format(parsed) == "@bob your TOWN request failed: Unable to assign a town"
  end

  test "formats completed responses" do
    json = ~s({"username":"carol","type":"COMPANY","completed":true,"error":null})
    assert {:ok, parsed} = Response.parse(json)
    assert Response.format(parsed) == "@carol your COMPANY request completed"
  end

  test "formats SET_TOWN_CREATION_ENABLED confirmed enabled response" do
    json =
      ~s({"username":"admin","type":"SET_TOWN_CREATION_ENABLED","completed":true,"error":null,"response":{"setting":"townCreationEnabled","enabled":true}})

    assert {:ok, parsed} = Response.parse(json)
    assert parsed.completed == true
    assert parsed.response == %{"setting" => "townCreationEnabled", "enabled" => true}
    assert Response.format(parsed) == "@admin town creation is now enabled"
  end

  test "formats SET_TOWN_CREATION_ENABLED confirmed disabled response" do
    json =
      ~s({"username":"admin","type":"SET_TOWN_CREATION_ENABLED","completed":true,"error":null,"response":{"setting":"townCreationEnabled","enabled":false}})

    assert {:ok, parsed} = Response.parse(json)
    assert parsed.completed == true
    assert parsed.response == %{"setting" => "townCreationEnabled", "enabled" => false}
    assert Response.format(parsed) == "@admin town creation is now disabled"
  end

  test "formats generic setting toggle responses" do
    json =
      ~s({"username":"admin","type":"SET_SOME_FEATURE_ENABLED","completed":true,"error":null,"response":{"setting":"someFeatureEnabled","enabled":true}})

    assert {:ok, parsed} = Response.parse(json)
    assert parsed.completed == true
    assert parsed.response == %{"setting" => "someFeatureEnabled", "enabled" => true}
    assert Response.format(parsed) == "@admin some feature is now enabled"
  end

  test "formats SET_TOWN_CREATION_ENABLED error response" do
    json =
      ~s({"username":"admin","type":"SET_TOWN_CREATION_ENABLED","completed":true,"error":"Town creation enabled value must be boolean","response":null})

    assert {:ok, parsed} = Response.parse(json)
    assert parsed.completed == true
    assert parsed.error == "Town creation enabled value must be boolean"

    assert Response.format(parsed) ==
             "@admin your SET_TOWN_CREATION_ENABLED request failed: Town creation enabled value must be boolean"
  end
end
