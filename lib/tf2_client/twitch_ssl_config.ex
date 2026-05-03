defmodule TF2Client.TwitchSSLConfig do
  @moduledoc false

  def options(host) when is_binary(host) do
    [
      verify: :verify_peer,
      cacertfile: CAStore.file_path(),
      server_name_indication: String.to_charlist(host),
      customize_hostname_check: [
        match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
      ]
    ]
  end
end
