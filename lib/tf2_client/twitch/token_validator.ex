defmodule TF2Client.Twitch.TokenValidator do
  @moduledoc false

  @validation_url "https://id.twitch.tv/oauth2/validate"

  def validate(password, username, request \\ &Finch.request/2) do
    token = String.replace_prefix(password, "oauth:", "")
    validation_request = Finch.build(:get, @validation_url, [{"authorization", "OAuth " <> token}])

    case request.(validation_request, TF2Client.Finch) do
      {:ok, %Finch.Response{status: 200, body: body}} -> validate_body(body, String.downcase(username))
      {:ok, %Finch.Response{status: 401}} -> {:error, :invalid_token}
      {:ok, %Finch.Response{status: status}} -> {:error, {:validation_unavailable, status}}
      {:error, _reason} -> {:error, :validation_unavailable}
    end
  end

  defp validate_body(body, username) do
    case Jason.decode(body) do
      {:ok, %{"login" => login, "scopes" => scopes}} when is_binary(login) and is_list(scopes) ->
        validate_identity(login, username, scopes)

      _other ->
        {:error, :invalid_validation_response}
    end
  end

  defp validate_identity(login, username, _scopes) when login != username,
    do: {:error, {:account_mismatch, login}}

  defp validate_identity(_login, _username, scopes) do
    case Enum.all?(["chat:read", "chat:edit"], &(&1 in scopes)) do
      true -> :ok
      false -> {:error, :missing_chat_scopes}
    end
  end
end
