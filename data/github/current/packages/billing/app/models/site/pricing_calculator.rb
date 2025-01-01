# typed: true
# frozen_string_literal: true

module Site
  class PricingCalculator
    sig { returns(ActiveSupport::HashWithIndifferentAccess) }
    def self.unit_prices
      @@unit_prices ||= HashWithIndifferentAccess.new(YAML.safe_load(Rails.root.join("config", "site", "pricing_calculator_unit_data.yml").read))
    end

    MACHINE_TYPES = [
      {
        name: "2 cores, 8GB RAM",
        size: "",
        description: "Static web apps, small databases, commandline applications",
        key: "codespaces_basic_machine",
        price_cents_usd: self.unit_prices[:codespaces_basic_machine][:value],
      },
      {
        name: "4 core, 16GB RAM",
        size: "",
        description: "Dynamic web apps, relational databases, analytics",
        key: "codespaces_standard_machine",
        price_cents_usd: self.unit_prices[:codespaces_standard_machine][:value],
      },
      {
        name: "8 core, 32GB RAM",
        size: "",
        description: "Multi-container applications, content management systems",
        key: "codespaces_premium_machine",
        price_cents_usd: self.unit_prices[:codespaces_premium_machine][:value],
      },
      {
        name: "16 core, 64GB RAM",
        size: "",
        description: "Compute-intensive database workloads, complex web apps",
        key: "codespaces_ultimate_machine",
        price_cents_usd: self.unit_prices[:codespaces_ultimate_machine][:value],
      },
      {
        name: "32 core, 128GB RAM",
        size: "",
        description: "Compute-intensive applications (AI and deep learning)",
        key: "codespaces_extreme_machine",
        price_cents_usd: self.unit_prices[:codespaces_extreme_machine][:value],
      },
    ].freeze

    OPERATING_SYSTEMS = [
      {
        label: "Ubuntu Linux",
        key: "action_runners_linux",
        price_cents_usd_per_hour: self.unit_prices[:action_runners_linux][:value] * 60,
      },
      {
        label: "Microsoft Windows",
        key: "action_runners_windows",
        price_cents_usd_per_hour: self.unit_prices[:action_runners_windows][:value] * 60,
      },
      {
        label: "macOS",
        key: "action_runners_macos",
        price_cents_usd_per_hour: self.unit_prices[:action_runners_macos][:value] * 60,
      },
    ]

    RUNNER_TYPES = [
      {
        label: "GitHub-managed Standard",
        description: "2 cores machine with default GitHub images.",
        key: "action_runners_standard"
      },
    ].freeze

    SCHEDULE_OPTIONS = [
      {
        label: "On schedule",
        key: "ghas_schedule_regular"
      },
      {
        label: "On every push to a pull request",
        key: "ghas_schedule_pr"
      },
      {
        label: "On schedule and on every push to a pull request",
        key: "ghas_schedule_both"
      },
    ].freeze

    LFS_INCLUDED_AMOUNTS = [
      {
        label: "Free plan",
        key: "lfs_free_amount_included",
        amount_included: self.unit_prices[:lfs_free_amount_included][:value]
      },
      {
        label: "Teams or Enterprise plan",
        key: "lfs_teams_enterprise_amount_included",
        amount_included: self.unit_prices[:lfs_teams_enterprise_amount_included][:value]
      },
    ].freeze

    SECTION_LINKS = [
      { label: "Codespaces", href: "#codespaces" },
      { label: "Actions", href: "#actions" },
      { label: "Packages", href: "#packages" },
      # { label: "LFS", href: "#lfs" },
      { label: "Advanced Security", href: "#security" },
    ].freeze
  end
end
