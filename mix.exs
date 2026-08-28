defmodule MyApp.MixProject do
  use Mix.Project

  def project do
    [
      app: :my_app,
      version: "0.1.0",
      elixir: "~> 1.20",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      compilers: [:phoenix_live_view] ++ Mix.compilers(),
      listeners: [Phoenix.CodeReloader],
      releases: releases(),
      dialyzer: dialyzer(),
      usage_rules: usage_rules()
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {MyApp.Application, []},
      extra_applications: [:logger, :runtime_tools, :os_mon]
    ]
  end

  def cli do
    [
      preferred_envs: [precommit: :test]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      # Phoenix / web
      {:phoenix, "~> 1.8.11"},
      {:phoenix_ecto, "~> 4.5"},
      {:ecto_sql, "~> 3.13"},
      {:postgrex, "~> 0.20"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 1.2.9"},
      {:lazy_html, ">= 0.1.0", only: :test},
      {:phoenix_live_dashboard, "~> 0.8.3"},
      {:ecto_psql_extras, "~> 0.8"},
      {:bandit, "~> 1.0"},
      {:dns_cluster, "~> 0.2.0"},
      {:gettext, "~> 1.0"},
      {:jason, "~> 1.2"},

      # Assets (no Node)
      {:esbuild, "~> 0.10", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.5", runtime: Mix.env() == :dev},
      {:heroicons,
       github: "tailwindlabs/heroicons",
       tag: "v2.2.0",
       sparse: "optimized",
       app: false,
       compile: false,
       depth: 1},
      {:daisyui,
       github: "saadeghi/daisyui",
       tag: "v5.5.20",
       sparse: "packages/bundle",
       app: false,
       compile: false,
       depth: 1},

      # Auth
      {:argon2_elixir, "~> 4.0"},

      # Email + HTTP
      {:swoosh, "~> 1.20"},
      {:req, "~> 0.5"},

      # Observability
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:prom_ex, "~> 1.12.0"},
      # The exporter is listed before the SDK and marked :permanent in releases/0
      # so that it outlives the SDK on shutdown.
      {:opentelemetry_exporter, "~> 1.10"},
      {:opentelemetry, "~> 1.7"},
      {:opentelemetry_api, "~> 1.5"},
      {:opentelemetry_phoenix, "~> 2.0"},
      {:opentelemetry_bandit, "~> 0.3.0"},
      {:opentelemetry_ecto, "~> 1.2"},
      {:logger_json, "~> 7.0"},

      # Dev / test tooling
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:igniter, "~> 0.8", only: [:dev, :test]},
      {:usage_rules, "~> 1.2", only: [:dev, :test]},
      {:tidewave, "~> 0.9", only: :dev},
      {:phoenix_test, "~> 0.12.1", only: :test, runtime: false},
      {:mox, "~> 1.2", only: :test},
      {:stream_data, "~> 1.0", only: [:dev, :test]}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get", "ecto.setup", "assets.setup", "assets.build"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["tailwind my_app", "esbuild my_app"],
      "assets.deploy": [
        "tailwind my_app --minify",
        "esbuild my_app --minify",
        "phx.digest"
      ],
      precommit: [
        "format --check-formatted",
        "deps.unlock --check-unused",
        "compile --warnings-as-errors",
        "credo --strict",
        "test"
      ]
    ]
  end

  # Release configuration. The OpenTelemetry exporter must be :permanent and
  # start before the (:temporary) SDK so that it outlives the SDK on shutdown.
  defp releases do
    [
      my_app: [
        applications: [
          opentelemetry_exporter: :permanent,
          opentelemetry: :temporary
        ]
      ]
    ]
  end

  # Dialyzer runs as a dedicated CI job (not in `mix precommit`). The PLTs live
  # under priv/plts so CI can cache them keyed on mix.lock.
  defp dialyzer do
    [
      plt_core_path: "priv/plts/core.plt",
      plt_local_path: "priv/plts/project.plt",
      plt_add_apps: [:mix, :ex_unit]
    ]
  end

  # usage_rules keeps the dependency usage rules in AGENTS.md's managed section
  # in sync with the installed versions. Run `mix usage_rules.sync` after every
  # dependency change and commit the result; CI fails on drift.
  defp usage_rules do
    [
      file: "AGENTS.md",
      usage_rules: [
        # usage_rules' own rules plus its built-in Elixir and OTP sub-rules.
        "usage_rules:all",
        # Phoenix ships its Phoenix.new-derived guidance as sub-rules
        # (elixir, html, ecto, liveview, phoenix); phoenix_* packages that
        # publish rules are picked up by the regex.
        "phoenix:all",
        ~r/^phoenix_/
      ]
    ]
  end
end
