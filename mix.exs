defmodule TF2Client.MixProject do
  use Mix.Project

  def project do
    [
      app: :tf2_client,
      version: "0.1.3",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      releases: releases()
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
      {:finch, "~> 0.18"},
      {:burrito, "~> 1.0", runtime: false}
    ]
  end

  defp releases do
    [
      tf2_client: [
        steps: [:assemble, &Burrito.wrap/1],
        burrito: [
          targets: [
            windows: [os: :windows, cpu: :x86_64]
          ]
        ]
      ]
    ]
  end
end
