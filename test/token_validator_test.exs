defmodule TF2Client.Twitch.TokenValidatorTest do
  use ExUnit.Case, async: true

  alias TF2Client.Twitch.TokenValidator

  test "validates the token with Twitch and accepts the configured account regardless of input casing" do
    request = fn request, TF2Client.Finch ->
      assert request.method == "GET"
      assert request.host == "id.twitch.tv"
      assert request.path == "/oauth2/validate"
      assert {"authorization", "OAuth test_token"} in request.headers
      {:ok, %Finch.Response{status: 200, body: Jason.encode!(%{login: "mybot", scopes: ["chat:read", "chat:edit"]})}}
    end

    assert :ok = TokenValidator.validate("oauth:test_token", "MyBot", request)
  end

  test "rejects authorization for a different Twitch account" do
    request = fn _, _ ->
      {:ok, %Finch.Response{status: 200, body: Jason.encode!(%{login: "otherbot", scopes: ["chat:read", "chat:edit"]})}}
    end

    assert {:error, {:account_mismatch, "otherbot"}} = TokenValidator.validate("token", "mybot", request)
  end

  test "rejects tokens without both IRC scopes" do
    request = fn _, _ ->
      {:ok, %Finch.Response{status: 200, body: Jason.encode!(%{login: "mybot", scopes: ["chat:read"]})}}
    end

    assert {:error, :missing_chat_scopes} = TokenValidator.validate("token", "mybot", request)
  end

  test "distinguishes revoked credentials from a Twitch outage" do
    rejected = fn _, _ -> {:ok, %Finch.Response{status: 401}} end
    unavailable = fn _, _ -> {:ok, %Finch.Response{status: 503}} end

    assert {:error, :invalid_token} = TokenValidator.validate("token", "mybot", rejected)
    assert {:error, {:validation_unavailable, 503}} = TokenValidator.validate("token", "mybot", unavailable)
  end

  test "malformed validation responses do not authorize the bot" do
    request = fn _, _ -> {:ok, %Finch.Response{status: 200, body: "not json"}} end
    assert {:error, :invalid_validation_response} = TokenValidator.validate("token", "mybot", request)
  end
end
