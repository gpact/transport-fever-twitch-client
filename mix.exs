defmodule TF2Client.MixProject do
  use Mix.Project

  def project do
    [
      app: :tf2_client,
      version: "1.0.1",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      dialyzer: [plt_file: {:no_warn, "priv/plts/project.plt"}, plt_add_apps: [:mix]],
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

  def cli do
    [preferred_envs: [check: :test]]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:tmi, "~> 0.7.0"},
      {:jason, "~> 1.4"},
      {:plug_cowboy, "~> 2.7"},
      {:finch, "~> 0.18"},
      {:castore, "~> 1.0"},
      {:burrito, "~> 1.5.0"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
    ]
  end

  defp aliases do
    [check: ["format --check-formatted", "credo --strict", "test"]]
  end

  defp releases do
    [
      tf2_client: [
        steps: [:assemble, &Burrito.wrap/1],
        burrito: [
          targets: [
            windows: [os: :windows, cpu: :x86_64],
            linux: [os: :linux, cpu: :x86_64],
            macos: [os: :darwin, cpu: :x86_64],
            macos_silicon: [os: :darwin, cpu: :aarch64]
          ]
        ]
      ]
    ]
  end
end
