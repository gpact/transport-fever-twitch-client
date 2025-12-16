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
end

