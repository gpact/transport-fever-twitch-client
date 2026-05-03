defmodule TF2Client.CLITest do
  use ExUnit.Case, async: false

  alias TF2Client.CLI

  setup do
    previous_args = System.argv()

    on_exit(fn -> System.argv(previous_args) end)

    :ok
  end

  test "detects dotted oauth bootstrap command" do
    System.argv(["oauth.bootstrap"])

    assert CLI.command() == :oauth_bootstrap
  end

  test "detects split oauth bootstrap command" do
    System.argv(["oauth", "bootstrap"])

    assert CLI.command() == :oauth_bootstrap
  end

  test "runs the bot by default" do
    System.argv([])

    assert CLI.command() == :run
  end
end
