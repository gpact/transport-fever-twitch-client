defmodule TF2Client.MixProject do
  use Mix.Project

  def project do
    [
      app: :tf2_client,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :crypto],
      mod: {TF2Client.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:tmi, "~> 0.7.0"},
      {:jason, "~> 1.4"},
      {:plug_cowboy, "~> 2.7"},
      {:finch, "~> 0.18"}
    ]
  end
end
