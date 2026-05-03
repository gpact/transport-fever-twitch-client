defmodule TF2Client.Twitch.TokenRefresher do
  @moduledoc false

  alias TF2Client.Twitch.TokenStore

  @default_redirect_uri "http://localhost:4000/oauth/callback"
  @token_url "https://id.twitch.tv/oauth2/token"
  @refresh_margin_seconds 60

  def irc_password do
    with {:ok, access_token} <- access_token() do
      {:ok, "oauth:" <> access_token}
    end
  end

  def access_token do
    store = TokenStore.default()

    case store.load() do
      {:ok, tokens} ->
        tokens = refresh_if_needed!(tokens, store)
        {:ok, tokens.access_token}

      :error ->
        {:error, :missing_tokens}
    end
  end

  def refresh! do
    store = TokenStore.default()

    case store.load() do
      {:ok, tokens} ->
        refreshed = refresh_tokens!(tokens.refresh_token)
        store.save(refreshed)
        {:ok, refreshed}

      :error ->
        {:error, :missing_tokens}
    end
  end

  def exchange_code_for_tokens!(code) when is_binary(code) do
    client_id = System.fetch_env!("TWITCH_CLIENT_ID")
    client_secret = System.fetch_env!("TWITCH_CLIENT_SECRET")
    redirect_uri = redirect_uri()

    params = %{
      client_id: client_id,
      client_secret: client_secret,
      code: code,
      grant_type: "authorization_code",
      redirect_uri: redirect_uri
    }

    response = post_form!(@token_url, params)
    decode_tokens!(response)
  end

  def request_with_bearer(method, url, headers, body \\ nil)
      when is_atom(method) and is_binary(url) and is_list(headers) do
    with {:ok, access_token} <- access_token() do
      headers = [{"authorization", "Bearer " <> access_token} | headers]
      request = Finch.build(method, url, headers, body)

      response = Finch.request(request, TF2Client.Finch)

      case response do
        {:ok, %Finch.Response{status: 401}} ->
          with {:ok, _tokens} <- refresh!(),
               {:ok, new_access_token} <- access_token() do
            headers = [{"authorization", "Bearer " <> new_access_token} | headers]
            request = Finch.build(method, url, headers, body)
            Finch.request(request, TF2Client.Finch)
          end

        other ->
          other
      end
    end
  end

  defp refresh_if_needed!(%{expires_at: expires_at} = tokens, store) when is_integer(expires_at) do
    now = System.os_time(:second)

    if expires_at - now <= @refresh_margin_seconds do
      refreshed = refresh_tokens!(tokens.refresh_token)
      store.save(refreshed)
      refreshed
    else
      tokens
    end
  end

  defp refresh_if_needed!(tokens, _store), do: tokens

  defp refresh_tokens!(refresh_token) when is_binary(refresh_token) do
    client_id = System.fetch_env!("TWITCH_CLIENT_ID")
    client_secret = System.fetch_env!("TWITCH_CLIENT_SECRET")

    params = %{
      client_id: client_id,
      client_secret: client_secret,
      grant_type: "refresh_token",
      refresh_token: refresh_token
    }

    response = post_form!(@token_url, params)
    decode_tokens!(response)
  end

  defp redirect_uri do
    case System.get_env("TWITCH_REDIRECT_URI") do
      value when is_binary(value) and value != "" -> value
      _other -> @default_redirect_uri
    end
  end

  defp post_form!(url, params) when is_binary(url) and is_map(params) do
    headers = [{"content-type", "application/x-www-form-urlencoded"}]
    body = URI.encode_query(params)
    request = Finch.build(:post, url, headers, body)

    case Finch.request(request, TF2Client.Finch) do
      {:ok, %Finch.Response{status: 200} = response} ->
        response

      {:ok, %Finch.Response{status: status}} ->
        raise "Twitch token request failed with HTTP status #{status}."

      {:error, _reason} ->
        raise "Twitch token request failed."
    end
  end

  defp decode_tokens!(%Finch.Response{body: body}) when is_binary(body) do
    decoded =
      case Jason.decode(body) do
        {:ok, %{} = json} -> json
        _ -> raise "Twitch token response was not valid JSON."
      end

    access_token = decoded |> Map.get("access_token") |> normalize_optional_string()
    refresh_token = decoded |> Map.get("refresh_token") |> normalize_optional_string()
    expires_in = decoded |> Map.get("expires_in") |> normalize_integer()

    if is_binary(access_token) and is_binary(refresh_token) and is_integer(expires_in) do
      now = System.os_time(:second)
      %{access_token: access_token, refresh_token: refresh_token, expires_at: now + expires_in}
    else
      raise "Twitch token response was missing required fields."
    end
  end

  defp normalize_integer(value) when is_integer(value), do: value
  defp normalize_integer(value) when is_float(value), do: trunc(value)
  defp normalize_integer(_), do: nil

  defp normalize_optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_optional_string(_), do: nil
end
