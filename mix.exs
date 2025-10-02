defmodule ReqVCR.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/Makesesama/req_vcr"

  def project do
    [
      app: :req_vcr,
      version: @version,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      docs: docs(),
      source_url: @source_url,
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test
      ],
      dialyzer: [
        plt_add_apps: [:mix],
        ignore_warnings: "dialyzer.ignore-warnings"
      ],
      aliases: aliases()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:req, "~> 0.5"},
      {:plug, "~> 1.16"},
      {:jason, "~> 1.4"},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.18", only: :test}
    ]
  end

  defp description do
    "VCR-style HTTP recording and replay for Req, with zero application code changes"
  end

  defp package do
    [
      name: "req_vcr",
      files: ~w[lib .formatter.exs mix.exs README.md CHANGELOG.md LICENSE],
      licenses: ["Apache-2.0"],
      links: %{
        "GitHub" => @source_url,
        "Changelog" => "#{@source_url}/blob/main/CHANGELOG.md"
      },
      maintainers: ["makussu"]
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md", "CHANGELOG.md"],
      source_url: @source_url,
      source_ref: "v#{@version}"
    ]
  end

  defp aliases do
    [
      precommit: [
        "format --check-formatted",
        "credo --strict",
        "dialyzer",
        "test"
      ]
    ]
  end
end
