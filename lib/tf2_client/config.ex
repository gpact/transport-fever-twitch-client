defmodule TF2Client.Config do
  @moduledoc false

  @default_client_id "l4my2fg4doyt5rpr0sow94d441jxxl"
  @default_redirect_uri "http://localhost:4000/oauth/callback"
  @default_config_filename "config.json"
  @app_dir "transport_fever"

  defstruct [
    :bot_user,
    :client_id,
    :client_secret,
    :bot_oauth,
    :game_files_path,
    channels: [],
    mod_channels: [],
    debug: false,
    redirect_uri: @default_redirect_uri,
    disable_rate_limits: false,
    enable_bot: true,
    transport_fever_version: :tf3
  ]

  @type t :: %__MODULE__{
          bot_user: String.t() | nil,
          channels: [String.t()],
          mod_channels: [String.t()],
          debug: boolean(),
          client_id: String.t() | nil,
          client_secret: String.t() | nil,
          redirect_uri: String.t(),
          bot_oauth: String.t() | nil,
          game_files_path: String.t() | nil,
          disable_rate_limits: boolean(),
          enable_bot: boolean(),
          transport_fever_version: :tf2 | :tf3
        }

  def config_path do
    case System.get_env("TF_CONFIG_PATH") do
      custom when is_binary(custom) and custom != "" ->
        custom

      _other ->
        local_path = Path.expand(@default_config_filename)

        case File.exists?(local_path) do
          true -> local_path
          false -> default_config_path()
        end
    end
  end

  def default_config_path do
    home = System.user_home!()
    Path.join([home, ".config", @app_dir, @default_config_filename])
  end

  def load(path \\ config_path()) do
    base_config =
      case File.read(path) do
        {:ok, content} ->
          case String.trim(content) do
            "" -> %__MODULE__{}
            trimmed -> parse_config_json(trimmed)
          end

        {:error, :enoent} ->
          %__MODULE__{}

        {:error, reason} ->
          {:error, {:file_read_error, reason}}
      end

    case base_config do
      {:error, reason} ->
        {:error, reason}

      %__MODULE__{} = config ->
        {:ok, apply_env_overrides(config)}
    end
  end

  def save(%__MODULE__{} = config, path \\ config_path()) do
    data = %{
      "bot_user" => config.bot_user,
      "channels" => config.channels,
      "mod_channels" => config.mod_channels,
      "debug" => config.debug,
      "client_id" => config.client_id,
      "client_secret" => config.client_secret,
      "bot_oauth" => config.bot_oauth,
      "redirect_uri" => config.redirect_uri,
      "disable_rate_limits" => config.disable_rate_limits,
      "enable_bot" => config.enable_bot,
      "transport_fever_version" => to_string(config.transport_fever_version)
    }

    clean_data = Map.new(Enum.reject(data, fn {_k, v} -> is_nil(v) end))

    json = Jason.encode!(clean_data, pretty: true)
    write_atomic_file!(path, json <> "\n")
  end

  def configured?(%__MODULE__{channels: channels, bot_user: bot_user}) do
    channels != [] and is_binary(bot_user) and String.trim(bot_user) != ""
  end

  def configured?(_), do: false

  def default_client_id, do: @default_client_id

  def client_id do
    case System.get_env("TWITCH_CLIENT_ID") do
      value when is_binary(value) and value != "" ->
        value

      _other ->
        case load() do
          {:ok, %__MODULE__{client_id: id}} when is_binary(id) and id != "" ->
            id

          _other ->
            @default_client_id
        end
    end
  end

  def client_secret do
    case System.get_env("TWITCH_CLIENT_SECRET") do
      value when is_binary(value) and value != "" ->
        value

      _other ->
        case load() do
          {:ok, %__MODULE__{client_secret: secret}} when is_binary(secret) and secret != "" ->
            secret

          _other ->
            nil
        end
    end
  end

  def implicit_flow? do
    case client_secret() do
      nil -> true
      "" -> true
      _secret -> false
    end
  end

  def implicit_flow?(%__MODULE__{client_secret: secret}) do
    case secret do
      nil -> true
      "" -> true
      _ -> false
    end
  end

  def redirect_uri do
    case System.get_env("TWITCH_REDIRECT_URI") do
      value when is_binary(value) and value != "" ->
        value

      _other ->
        case load() do
          {:ok, %__MODULE__{redirect_uri: uri}} when is_binary(uri) and uri != "" ->
            uri

          _other ->
            @default_redirect_uri
        end
    end
  end

  def summary do
    case load() do
      {:ok, config} -> summary(config)
      {:error, reason} -> "Error loading configuration: #{inspect(reason)}"
    end
  end

  def summary(%__MODULE__{} = config) do
    """
    ========================================================
        Transport Fever Twitch Bot - Configuration
    ========================================================
    Config Path:    #{config_path()}
    Bot Username:   #{config.bot_user || "(not set)"}
    Channels:       #{format_list(config.channels)}
    Client ID:      #{client_id_status(config.client_id)}
    Client Secret:  #{client_secret_status(config.client_secret)}
    Debug Mode:     #{config.debug}
    Rate Limits:    #{rate_limit_status(config.disable_rate_limits)}
    Bot Enabled:    #{config.enable_bot}
    TF Version:     #{config.transport_fever_version}
    """
  end

  defp format_list([]), do: "(none)"
  defp format_list(list) when is_list(list), do: Enum.join(list, ", ")

  defp client_id_status(nil), do: "project default (#{@default_client_id})"
  defp client_id_status(""), do: "project default (#{@default_client_id})"
  defp client_id_status(id) when id == @default_client_id, do: "project default (#{id})"
  defp client_id_status(_custom), do: "custom configured"

  defp client_secret_status(nil), do: "not set (using browser login)"
  defp client_secret_status(""), do: "not set (using browser login)"
  defp client_secret_status(_), do: "configured"

  defp rate_limit_status(true), do: "disabled"
  defp rate_limit_status(false), do: "enabled"

  defp parse_config_json(content) when is_binary(content) do
    case Jason.decode(content) do
      {:ok, %{} = map} ->
        from_map(map)

      {:error, reason} ->
        {:error, {:invalid_json, reason}}
    end
  end

  defp from_map(map) when is_map(map) do
    %__MODULE__{
      bot_user: fetch_string(map, ["bot_user", "twitch_bot_user"]),
      channels: fetch_string_list(map, ["channels", "twitch_channels"]),
      mod_channels: fetch_string_list(map, ["mod_channels", "twitch_mod_channels"]),
      debug: fetch_bool(map, ["debug", "twitch_debug"], false),
      client_id: fetch_string(map, ["client_id", "twitch_client_id"]),
      client_secret: fetch_string(map, ["client_secret", "twitch_client_secret"]),
      redirect_uri: fetch_string(map, ["redirect_uri", "twitch_redirect_uri"]) || @default_redirect_uri,
      bot_oauth: fetch_string(map, ["bot_oauth", "twitch_bot_oauth"]),
      game_files_path: fetch_string(map, ["game_files_path", "tf_integration_game_files"]),
      disable_rate_limits: fetch_bool(map, ["disable_rate_limits", "tf_disable_rate_limits"], false),
      enable_bot: fetch_bool(map, ["enable_bot", "tf_enable_twitch_bot"], true),
      transport_fever_version: fetch_version(map, ["transport_fever_version", "game_version"])
    }
  end

  defp apply_env_overrides(%__MODULE__{} = config) do
    %__MODULE__{
      config
      | bot_user: env_override("TWITCH_BOT_USER", config.bot_user),
        channels: env_override_list("TWITCH_CHANNELS", config.channels),
        mod_channels: env_override_list("TWITCH_MOD_CHANNELS", config.mod_channels),
        debug: env_override_bool("TWITCH_DEBUG", config.debug),
        client_id: env_override("TWITCH_CLIENT_ID", config.client_id),
        client_secret: env_override("TWITCH_CLIENT_SECRET", config.client_secret),
        redirect_uri: env_override("TWITCH_REDIRECT_URI", config.redirect_uri),
        bot_oauth: env_override("TWITCH_BOT_OAUTH", config.bot_oauth),
        game_files_path: env_override("TF_INTEGRATION_GAME_FILES", config.game_files_path),
        disable_rate_limits: env_override_bool("TF_DISABLE_RATE_LIMITS", config.disable_rate_limits),
        enable_bot: env_override_bool("TF_ENABLE_TWITCH_BOT", config.enable_bot),
        transport_fever_version: env_override_version("TRANSPORT_FEVER_VERSION", config.transport_fever_version)
    }
  end

  defp fetch_version(map, keys) when is_map(map) and is_list(keys) do
    case fetch_string(map, keys) do
      nil -> :tf3
      val -> TF2Client.TransportFever.parse_version(val)
    end
  end

  defp env_override_version(key, default) when is_binary(key) do
    case System.get_env(key) do
      nil -> default
      "" -> default
      val -> TF2Client.TransportFever.parse_version(val)
    end
  end

  defp env_override(key, default) when is_binary(key) do
    case System.get_env(key) do
      nil -> default
      "" -> default
      value -> String.trim(value)
    end
  end

  defp env_override_list(key, default) do
    case System.get_env(key) do
      nil ->
        default

      value ->
        split_string_list(value)
    end
  end

  defp env_override_bool(key, default) when is_binary(key) do
    case System.get_env(key) do
      nil -> default
      value -> parse_bool_value(value, default)
    end
  end

  defp fetch_string(map, keys) when is_map(map) and is_list(keys) do
    Enum.find_value(keys, fn key ->
      case Map.get(map, key) do
        val when is_binary(val) ->
          case String.trim(val) do
            "" -> nil
            trimmed -> trimmed
          end

        _ ->
          nil
      end
    end)
  end

  defp fetch_string_list(map, keys) when is_map(map) and is_list(keys) do
    Enum.find_value(keys, [], fn key ->
      case Map.get(map, key) do
        list when is_list(list) ->
          Enum.filter(list, &is_binary/1)
          |> Enum.map(&String.trim/1)
          |> Enum.reject(&(&1 == ""))

        binary when is_binary(binary) ->
          split_string_list(binary)

        _ ->
          nil
      end
    end)
  end

  defp fetch_bool(map, keys, default) when is_map(map) and is_list(keys) do
    Enum.find_value(keys, default, fn key ->
      case Map.get(map, key) do
        val when is_boolean(val) -> val
        val when is_binary(val) -> parse_bool_value(val, default)
        _ -> nil
      end
    end)
  end

  defp parse_bool_value(value, default) when is_binary(value) do
    case String.downcase(String.trim(value)) do
      "1" -> true
      "true" -> true
      "yes" -> true
      "0" -> false
      "false" -> false
      "no" -> false
      _ -> default
    end
  end

  defp split_string_list(value) when is_binary(value) do
    String.split(value, [",", " "], trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp write_atomic_file!(path, contents) when is_binary(path) and is_binary(contents) do
    dir = Path.dirname(path)
    File.mkdir_p!(dir)
    maybe_chmod(dir, 0o700)

    tmp_path = path <> ".tmp"
    File.write!(tmp_path, contents)
    maybe_chmod(tmp_path, 0o600)
    File.rename!(tmp_path, path)
    :ok
  end

  defp maybe_chmod(path, mode) when is_binary(path) and is_integer(mode) do
    case :os.type() do
      {:win32, _} -> :ok
      _ -> File.chmod(path, mode)
    end

    :ok
  end
end
