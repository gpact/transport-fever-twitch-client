defmodule TF2Client.Twitch.TokenRefresher do
  @moduledoc false

  alias TF2Client.Config
  alias TF2Client.Twitch.TokenStore

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
        case refresh_if_needed(tokens, store) do
          {:ok, refreshed_tokens} ->
            {:ok, refreshed_tokens.access_token}

          {:error, _reason} ->
            {:error, :missing_tokens}
        end

      :error ->
        {:error, :missing_tokens}
    end
  end

  def refresh! do
    store = TokenStore.default()

    case store.load() do
      {:ok, %{refresh_token: refresh_token}} when is_binary(refresh_token) and refresh_token != "" ->
        case refresh_tokens(refresh_token) do
          {:ok, refreshed} ->
            store.save(refreshed)
            {:ok, refreshed}

          {:error, reason} ->
            store.delete()
            {:error, reason}
        end

      {:ok, _tokens} ->
        store.delete()
        {:error, :missing_refresh_token}

      :error ->
        {:error, :missing_tokens}
    end
  end

  def exchange_code_for_tokens!(code) when is_binary(code) do
    client_id = Config.client_id()
    client_secret = Config.client_secret() || raise "Twitch Client Secret required to exchange authorization code."
    redirect_uri = Config.redirect_uri()

    params = %{
      client_id: client_id,
      client_secret: client_secret,
      code: code,
      grant_type: "authorization_code",
      redirect_uri: redirect_uri
    }

    case post_form(@token_url, params) do
      {:ok, %Finch.Response{status: 200} = response} ->
        case decode_tokens(response) do
          {:ok, tokens} -> tokens
          {:error, reason} -> raise "Twitch token response was invalid: #{inspect(reason)}"
        end

      {:ok, %Finch.Response{status: status, body: body}} ->
        raise "Twitch token exchange failed with HTTP status #{status}: #{body}"

      {:error, reason} ->
        raise "Twitch token exchange failed: #{inspect(reason)}"
    end
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

  defp refresh_if_needed(%{expires_at: expires_at} = tokens, store) when is_integer(expires_at) do
    now = System.os_time(:second)

    case expires_at - now <= @refresh_margin_seconds do
      true ->
        attempt_refresh(tokens, store)

      false ->
        {:ok, tokens}
    end
  end

  defp refresh_if_needed(tokens, _store), do: {:ok, tokens}

  defp attempt_refresh(%{refresh_token: refresh_token} = _tokens, store)
       when is_binary(refresh_token) and refresh_token != "" do
    case refresh_tokens(refresh_token) do
      {:ok, refreshed} ->
        store.save(refreshed)
        {:ok, refreshed}

      {:error, reason} ->
        store.delete()
        {:error, reason}
    end
  end

  defp attempt_refresh(_tokens, store) do
    store.delete()
    {:error, :token_expired}
  end

  defp refresh_tokens(refresh_token) when is_binary(refresh_token) do
    client_id = Config.client_id()
    client_secret = Config.client_secret() || ""

    params = %{
      client_id: client_id,
      client_secret: client_secret,
      grant_type: "refresh_token",
      refresh_token: refresh_token
    }

    case post_form(@token_url, params) do
      {:ok, response} ->
        decode_tokens(response)

      other ->
        other
    end
  end

  defp post_form(url, params) when is_binary(url) and is_map(params) do
    headers = [{"content-type", "application/x-www-form-urlencoded"}]
    body = URI.encode_query(params)
    request = Finch.build(:post, url, headers, body)

    case Finch.request(request, TF2Client.Finch) do
      {:ok, %Finch.Response{status: 200} = response} ->
        {:ok, response}

      {:ok, %Finch.Response{} = response} ->
        {:ok, response}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp decode_tokens(%Finch.Response{status: 200, body: body}) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, %{} = json} ->
        extract_token_fields(json)

      _ ->
        {:error, :invalid_json}
    end
  end

  defp decode_tokens(%Finch.Response{status: status, body: body}) do
    {:error, {:http_error, status, body}}
  end

  defp extract_token_fields(json) when is_map(json) do
    access_token = normalize_optional_string(Map.get(json, "access_token"))
    refresh_token = normalize_optional_string(Map.get(json, "refresh_token"))
    expires_in = normalize_integer(Map.get(json, "expires_in"))

    case {access_token, refresh_token, expires_in} do
      {at, rt, exp} when is_binary(at) and is_binary(rt) and is_integer(exp) ->
        now = System.os_time(:second)
        {:ok, %{access_token: at, refresh_token: rt, expires_at: now + exp}}

      _other ->
        {:error, :missing_fields}
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
