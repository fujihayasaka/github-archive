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
        label: "Linux",
        key: "action_runners_linux",
      },
      {
        label: "Windows",
        key: "action_runners_windows",
      },
      {
        label: "macOS",
        key: "action_runners_macos",
      },
    ].freeze

    RUNNER_TYPES = [
      {
        label: "x64",
        key: "action_runners_x64",
      },
      {
        label: "ARM64",
        key: "action_runners_arm64",
      },
      {
        label: "GPU-powered",
        key: "action_runners_gpu",
      },
    ].freeze

    CORE_SIZES_LINUX_X64 = [
      {
        label: "1-core",
        runner: "Linux 1-core (x64)",
        key: "action_runners_linux_x64_1core",
        price_cents_usd_per_min: self.unit_prices[:action_runners_linux_x64_1core][:value],
      },
      {
        label: "2-core",
        runner: "Linux 2-core (x64)",
        key: "action_runners_linux_x64_2core",
        price_cents_usd_per_min: self.unit_prices[:action_runners_linux_x64_2core][:value],
      },
      {
        label: "4-core",
        runner: "Linux 4-core (x64)",
        key: "action_runners_linux_x64_4core",
        price_cents_usd_per_min: self.unit_prices[:action_runners_linux_x64_4core][:value],
      },
      {
        label: "8-core",
        runner: "Linux 8-core (x64)",
        key: "action_runners_linux_x64_8core",
        price_cents_usd_per_min: self.unit_prices[:action_runners_linux_x64_8core][:value],
      },
      {
        label: "16-core",
        runner: "Linux 16-core (x64)",
        key: "action_runners_linux_x64_16core",
        price_cents_usd_per_min: self.unit_prices[:action_runners_linux_x64_16core][:value],
      },
      {
        label: "32-core",
        runner: "Linux 32-core (x64)",
        key: "action_runners_linux_x64_32core",
        price_cents_usd_per_min: self.unit_prices[:action_runners_linux_x64_32core][:value],
      },
      {
        label: "64-core",
        runner: "Linux 64-core (x64)",
        key: "action_runners_linux_x64_64core",
        price_cents_usd_per_min: self.unit_prices[:action_runners_linux_x64_64core][:value],
      },
      {
        label: "96-core",
        runner: "Linux 96-core (x64)",
        key: "action_runners_linux_x64_96core",
        price_cents_usd_per_min: self.unit_prices[:action_runners_linux_x64_96core][:value],
      },
    ].freeze

    CORE_SIZES_LINUX_ARM64 = [
      {
        label: "2-core",
        runner: "Linux 2-core (ARM64)",
        key: "action_runners_linux_arm64_2core",
        price_cents_usd_per_min: self.unit_prices[:action_runners_linux_arm64_2core][:value],
      },
      {
        label: "4-core",
        runner: "Linux 4-core (ARM64)",
        key: "action_runners_linux_arm64_4core",
        price_cents_usd_per_min: self.unit_prices[:action_runners_linux_arm64_4core][:value],
      },
      {
        label: "8-core",
        runner: "Linux 8-core (ARM64)",
        key: "action_runners_linux_arm64_8core",
        price_cents_usd_per_min: self.unit_prices[:action_runners_linux_arm64_8core][:value],
      },
      {
        label: "16-core",
        runner: "Linux 16-core (ARM64)",
        key: "action_runners_linux_arm64_16core",
        price_cents_usd_per_min: self.unit_prices[:action_runners_linux_arm64_16core][:value],
      },
      {
        label: "32-core",
        runner: "Linux 32-core (ARM64)",
        key: "action_runners_linux_arm64_32core",
        price_cents_usd_per_min: self.unit_prices[:action_runners_linux_arm64_32core][:value],
      },
      {
        label: "64-core",
        runner: "Linux 64-core (ARM64)",
        key: "action_runners_linux_arm64_64core",
        price_cents_usd_per_min: self.unit_prices[:action_runners_linux_arm64_64core][:value],
      },
    ].freeze

    CORE_SIZES_LINUX_GPU = [
      {
        label: "4-core",
        runner: "Linux 4-core w/ GPU (x64)",
        key: "action_runners_linux_gpu_4core",
        price_cents_usd_per_min: self.unit_prices[:action_runners_linux_gpu_4core][:value],
      },
    ].freeze

    CORE_SIZES_WINDOWS_X64 = [
      {
        label: "Server 2-core",
        runner: "Windows Server 2-core (x64)",
        key: "action_runners_windows_x64_2core",
        price_cents_usd_per_min: self.unit_prices[:action_runners_windows_x64_2core][:value],
      },
      {
        label: "Desktop 4-core",
        runner: "Windows Desktop 4-core (x64)",
        key: "action_runners_windows_x64_4core",
        price_cents_usd_per_min: self.unit_prices[:action_runners_windows_x64_4core][:value],
      },
      {
        label: "Server 8-core",
        runner: "Windows Server 8-core (x64)",
        key: "action_runners_windows_x64_8core",
        price_cents_usd_per_min: self.unit_prices[:action_runners_windows_x64_8core][:value],
      },
      {
        label: "Server 16-core",
        runner: "Windows Server 16-core (x64)",
        key: "action_runners_windows_x64_16core",
        price_cents_usd_per_min: self.unit_prices[:action_runners_windows_x64_16core][:value],
      },
      {
        label: "Server 32-core",
        runner: "Windows Server 32-core (x64)",
        key: "action_runners_windows_x64_32core",
        price_cents_usd_per_min: self.unit_prices[:action_runners_windows_x64_32core][:value],
      },
      {
        label: "Server 64-core",
        runner: "Windows Server 64-core (x64)",
        key: "action_runners_windows_x64_64core",
        price_cents_usd_per_min: self.unit_prices[:action_runners_windows_x64_64core][:value],
      },
      {
        label: "Server 96-core",
        runner: "Windows Server 96-core (x64)",
        key: "action_runners_windows_x64_96core",
        price_cents_usd_per_min: self.unit_prices[:action_runners_windows_x64_96core][:value],
      },
    ].freeze

    CORE_SIZES_WINDOWS_ARM64 = [
      {
        label: "Desktop 2-core",
        runner: "Windows Desktop 2-core (ARM64)",
        key: "action_runners_windows_arm64_2core",
        price_cents_usd_per_min: self.unit_prices[:action_runners_windows_arm64_2core][:value],
      },
      {
        label: "Desktop 4-core",
        runner: "Windows Desktop 4-core (ARM64)",
        key: "action_runners_windows_arm64_4core",
        price_cents_usd_per_min: self.unit_prices[:action_runners_windows_arm64_4core][:value],
      },
      {
        label: "Desktop 8-core",
        runner: "Windows Desktop 8-core (ARM64)",
        key: "action_runners_windows_arm64_8core",
        price_cents_usd_per_min: self.unit_prices[:action_runners_windows_arm64_8core][:value],
      },
      {
        label: "Desktop 16-core",
        runner: "Windows Desktop 16-core (ARM64)",
        key: "action_runners_windows_arm64_16core",
        price_cents_usd_per_min: self.unit_prices[:action_runners_windows_arm64_16core][:value],
      },
      {
        label: "Desktop 32-core",
        runner: "Windows Desktop 32-core (ARM64)",
        key: "action_runners_windows_arm64_32core",
        price_cents_usd_per_min: self.unit_prices[:action_runners_windows_arm64_32core][:value],
      },
      {
        label: "Desktop 64-core",
        runner: "Windows Desktop 64-core (ARM64)",
        key: "action_runners_windows_arm64_64core",
        price_cents_usd_per_min: self.unit_prices[:action_runners_windows_arm64_64core][:value],
      },
    ].freeze

    CORE_SIZES_WINDOWS_GPU = [
      {
        label: "4-core",
        runner: "Windows Server 4-core w/ GPU (x64)",
        key: "action_runners_windows_gpu_4core",
        price_cents_usd_per_min: self.unit_prices[:action_runners_windows_gpu_4core][:value],
      },
    ].freeze

    CORE_SIZES_MACOS_X64 = [
      {
        label: "4-core (Intel)",
        runner: "macOS 4-core (Intel-x64)",
        key: "action_runners_macos_x64_4core",
        price_cents_usd_per_min: self.unit_prices[:action_runners_macos_x64_4core][:value],
      },
      {
        label: "12-core (Intel)",
        runner: "macOS 12-core (Intel-x64)",
        key: "action_runners_macos_x64_12core",
        price_cents_usd_per_min: self.unit_prices[:action_runners_macos_x64_12core][:value],
      },
    ].freeze

    CORE_SIZES_MACOS_ARM64 = [
      {
        label: "3-core (M1)",
        runner: "macOS 3-core (M1)",
        key: "action_runners_macos_arm64_3core",
        price_cents_usd_per_min: self.unit_prices[:action_runners_macos_arm64_3core][:value],
      },
      {
        label: "5-core (M2 Pro)",
        runner: "macOS 5-core (M2 Pro)",
        key: "action_runners_macos_arm64_5core",
        price_cents_usd_per_min: self.unit_prices[:action_runners_macos_arm64_5core][:value],
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

    COPILOT_PLANS = [
      {
        key: "copilot_free",
        name: "Free",
        user_type: "individual",
        description: "For individual developers: 2,000 completions and 50 chat requests per month",
        price_cents_usd: 0
      },
      {
        key: "copilot_pro",
        name: "Pro",
        user_type: "individual",
        description: "For individual developers: Unlimited code completion, chat assistance, and mobile access",
        price_cents_usd: 1000
      },
      {
        key: "copilot_pro_plus",
        name: "Pro+",
        user_type: "individual",
        description: "For individual developers: Maximum flexibility and model choice",
        price_cents_usd: 3900
      },
      {
        key: "copilot_business",
        name: "Business",
        user_type: "organization",
        description: "For organizations: Team-wide AI pair programming with enterprise-grade security and management",
        price_cents_usd: 1900
      },
      {
        key: "copilot_enterprise",
        name: "Enterprise",
        user_type: "organization",
        description: "For organizations: Custom deployment with advanced security, compliance, and policy controls",
        price_cents_usd: 3900
      }
    ].freeze

    SECTION_LINKS = [
      { label: "GitHub Copilot", href: "#copilot" },
      { label: "Codespaces", href: "#codespaces" },
      { label: "Actions", href: "#actions" },
      { label: "Advanced Security", href: "#security" },
    ].freeze
  end
end
