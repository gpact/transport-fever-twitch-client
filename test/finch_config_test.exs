defmodule TF2Client.FinchConfigTest do
  use ExUnit.Case, async: true

  alias TF2Client.FinchConfig

  test "configures Finch with an explicit CA certificate file" do
    assert [cacertfile: cacertfile] = FinchConfig.transport_opts()
    assert is_binary(cacertfile)
    assert File.regular?(cacertfile)
  end
end
