# typed: true
# frozen_string_literal: true

class Billing::ActionsUsage < Billing::BaseUsage
  attr_reader :client_wrapper, :minutes_used_per_runtime_from_api
  STANDARD_RUNNERS = %w[MACOS UBUNTU WINDOWS]
  CUSTOM_RUNNERS = %w[ubuntu_4_core ubuntu_8_core ubuntu_16_core ubuntu_32_core ubuntu_64_core
                    windows_4_core windows_8_core windows_16_core windows_32_core windows_64_core]
  MACOS_RUNNERS = ["macos_12_core"]

  def initialize(billable_owner, owner: nil, additional_private_minutes: 0, starts_at: nil, shared_usage: nil, usage_quote: {})
    super(billable_owner, owner: owner, starts_at: starts_at, shared_usage: shared_usage)

    if usage_quote.present?
      proposed_private_usage_from_usage_quote_api!([usage_quote])
    end
    @additional_private_minutes = additional_private_minutes
  end

  def self.product_usage(account, additional_private_minutes: 0, starts_at: nil, shared_usage: nil)
    owner, billable_owner = owner_and_billable_owner_from(account)
    instance = new(billable_owner, owner: owner, additional_private_minutes: additional_private_minutes, starts_at: starts_at, shared_usage: shared_usage)

    start_time = Time.current
    instance.fetch_product_usage(account)
    end_time = Time.current

    GitHub.dogstats.distribution(
      "actions_billing.fetch_product_usage", (end_time - start_time) * 1_000,
      tags: ["flag:#{FeatureFlag.vexi.enabled_or_raise?(:custom_runners_spending_limit_bug, billable_owner)}"] # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
    )

    instance
  end

  def self.usage_quote(account, additional_private_minutes: 0)
    owner, billable_owner = owner_and_billable_owner_from(account)
    instance = new(billable_owner, owner: owner)
    instance.fetch_usage_quote(account: account, additional_private_minutes: additional_private_minutes)
    instance
  end

  def self.account_usage(account, shared_usage: nil)
    owner, billable_owner = owner_and_billable_owner_from(account)
    instance = new(billable_owner, owner: owner, shared_usage: shared_usage)

    start_time = Time.current
    instance.fetch_accounts_usage(account, owner)
    end_time = Time.current

    GitHub.dogstats.distribution(
      "actions_billing.fetch_account_usage", (end_time - start_time) * 1_000,
      tags: ["flag:#{FeatureFlag.vexi.enabled_or_raise?(:custom_runners_spending_limit_bug, billable_owner)}"] # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
    )

    instance
  end

  def included_minutes
    plan.actions_included_private_minutes
  end

  def total_minutes_used
    minutes_used_per_runtime["total"] + additional_private_minutes
  end

  def total_paid_minutes_used
    total_paid_standard_runners_minutes_used + total_custom_runners_minutes_used + total_macos_runners_minutes_used
  end

  def total_standard_runners_minutes_used
    minutes_used_per_runtime["total"] - total_custom_runners_minutes_used - total_macos_runners_minutes_used
  end

  def total_paid_standard_runners_minutes_used
    [0, total_standard_runners_minutes_used + additional_private_minutes - included_minutes].max
  end

  def total_custom_runners_minutes_used
    minutes_used_per_runtime.select { |r| CUSTOM_RUNNERS.include?(r) }.reject { |r| r == "total" }.values.sum
  end

  def total_macos_runners_minutes_used
    minutes_used_per_runtime.select { |r| MACOS_RUNNERS.include?(r) }.reject { |r| r == "total" }.values.sum
  end

  def used_up_entitlements?
    total_standard_runners_minutes_used >= included_minutes
  end

  def entitlement_minutes_used_percentage
    return 100 if included_minutes.zero?
    percent = (total_standard_runners_minutes_used / Float(included_minutes)).round(2)
    [100, (percent * 100).to_i].min
  end

  # Returns Billing::Money
  def total_billable_usage_pricing
    response = list_products_api_call(products: ["actions"])
    sku_usage = aggregate_by_sku_usage(response[:product_usage], product: "actions")
    estimated_cost = (
      billable_pricing_standard_runners(sku_usage) +
      billable_pricing_custom_runners(sku_usage) +
      billable_pricing_macos_runners(sku_usage)
    )

    Billing::Money.new(estimated_cost)
  end

  def billable_pricing_standard_runners(usage)
    effective_quantity = Billing::Actions::MEUSE_STANDARD_RUNNERS.sum do |sku|
      usage[sku][:effective_quantity].to_i
    end

    effective_quantity = [0, effective_quantity + additional_private_minutes - included_minutes].max
    effective_quantity * plan.actions_overage_unit_cost_cents
  end

  def billable_pricing_custom_runners(usage)
    Billing::Actions::MEUSE_CUSTOM_RUNNERS.sum { |sku| usage[sku][:estimated_cost].to_i }
  end

  def billable_pricing_macos_runners(usage)
    Billing::Actions::MACOS_RUNNERS.sum { |sku| usage[sku][:estimated_cost].to_i }
  end

  # Returns Hash
  # Public: Returns the rounded billable minutes executed for private repositories
  # for the user, both broken down by job_runtime_environment and as a total.
  #
  # Example response:
  # { "UBUNTU"=>20, "MACOS"=>1, "WINDOWS"=>3, "TOTAL"=>24 }
  #
  # Returns Hash
  def minutes_used_per_runtime
    return @minutes_used_per_runtime if defined?(@minutes_used_per_runtime)

    @minutes_used_per_runtime = minutes_used_per_runtime_from_api
  end

  def fetch_usage_quote(account:, additional_private_minutes: 0)
    if FeatureFlag.vexi.enabled_or_raise?(:actions_product_usage_refactor, billable_owner) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
      proposed_usage = [{
        product_sku_name: :linux,
        proposed_quantity: additional_private_minutes,
        entitlement_quantity: included_minutes,
      }]
      response = Billing::Usage::Actions::CalculateUsageQuotes.new(
        proposed_usage: proposed_usage, account: account, starts_at: starts_at
      ).call

      unless response.error?
        @minutes_used_per_runtime_from_api = response.content.to_h
      end
    else
      proposed_usage = [{
        product_name: :actions,
        product_sku_name: :linux,
        proposed_quantity: additional_private_minutes,
        entitlement_quantity: included_minutes,
      }]
      response = usage_quotes_api_call(proposed_usage)

      unless error_response?(response)
        proposed_private_usage_from_usage_quote_api!(response[:usage_quotes])
      end
    end
  end

  def fetch_product_usage(account)
    if FeatureFlag.vexi.enabled_or_raise?(:actions_product_usage_refactor, billable_owner) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
      usage = Billing::Usage::Actions::FetchProductUsage.new(account: account, starts_at: starts_at).call.content
      @minutes_used_per_runtime_from_api = usage.to_h
      return
    end

    response = list_products_api_call(products: ["actions"])
    if error_response?(response)
      @minutes_used_per_runtime_from_api = {
        "UBUNTU" => 0,
        "MACOS" => 0,
        "WINDOWS" => 0,
        "ubuntu_4_core" => 0,
        "ubuntu_8_core" => 0,
        "ubuntu_16_core" => 0,
        "ubuntu_32_core" => 0,
        "ubuntu_64_core" => 0,
        "windows_4_core" => 0,
        "windows_8_core" => 0,
        "windows_16_core" => 0,
        "windows_32_core" => 0,
        "windows_64_core" => 0,
        "macos_12_core" => 0,
        "total" => 0
    }
    else
      private_usage_from_product_list_api!(response[:product_usage])
    end
  end

  def fetch_accounts_usage(account, owner)
    if FeatureFlag.vexi.enabled_or_raise?(:actions_product_usage_refactor, billable_owner) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
      usage = Billing::Usage::Actions::FetchAccountUsage.new(account: account, starts_at: starts_at).call.content
      @minutes_used_per_runtime_from_api = usage.to_h
      return
    end

    response = list_accounts_api_call(products: ["actions"])
    if error_response?(response)
      @minutes_used_per_runtime_from_api = {
        "UBUNTU" => 0,
        "MACOS" => 0,
        "WINDOWS" => 0,
        "ubuntu_4_core" => 0,
        "ubuntu_8_core" => 0,
        "ubuntu_16_core" => 0,
        "ubuntu_32_core" => 0,
        "ubuntu_64_core" => 0,
        "windows_4_core" => 0,
        "windows_8_core" => 0,
        "windows_16_core" => 0,
        "windows_32_core" => 0,
        "windows_64_core" => 0,
        "macos_12_core" => 0,
        "total" => 0
      }
    else
      accounts_usage = response[:account_usage]
      accounts_usage = accounts_usage.select { |usage| usage[:account][:account_id] == owner.id } if owner.present?
      products_usage = accounts_usage.map { |usage| usage[:product_usage] }.flatten

      private_usage_from_product_list_api!(products_usage)
    end
  end

  private

  attr_reader :billable_owner, :plan, :owner, :additional_private_minutes, :starts_at

  def proposed_private_usage_from_usage_quote_api!(usage_quotes)
    quote = usage_quotes.detect(&:actions_linux?)

    @minutes_used_per_runtime_from_api = {
      "total" => quote.proposed_effective_quantity
    }

    @usage_billable_quantity = quote.proposed_billable_quantity
    @usage_estimated_cost = quote.proposed_estimated_cost
  end

  def private_usage_from_product_list_api!(products_usage)
    sku_usage = aggregate_by_sku_usage(products_usage, product: "actions")

    linux_effective_quantity = sku_usage["linux"][:effective_quantity]
    macos_effective_quantity = sku_usage["macos"][:effective_quantity]
    windows_effective_quantity = sku_usage["windows"][:effective_quantity]

    total = linux_effective_quantity + macos_effective_quantity + windows_effective_quantity
    standard_minutes = {
      "UBUNTU" => linux_effective_quantity,
      "MACOS" => macos_effective_quantity,
      "WINDOWS" => windows_effective_quantity
    }

    linux_4_core_effective_quantity = sku_usage["linux_4_core"][:effective_quantity]
    linux_8_core_effective_quantity = sku_usage["linux_8_core"][:effective_quantity]
    linux_16_core_effective_quantity = sku_usage["linux_16_core"][:effective_quantity]
    linux_32_core_effective_quantity = sku_usage["linux_32_core"][:effective_quantity]
    linux_64_core_effective_quantity = sku_usage["linux_64_core"][:effective_quantity]
    windows_4_core_effective_quantity = sku_usage["windows_4_core"][:effective_quantity]
    windows_8_core_effective_quantity = sku_usage["windows_8_core"][:effective_quantity]
    windows_16_core_effective_quantity = sku_usage["windows_16_core"][:effective_quantity]
    windows_32_core_effective_quantity = sku_usage["windows_32_core"][:effective_quantity]
    windows_64_core_effective_quantity = sku_usage["windows_64_core"][:effective_quantity]

    custom_runner_total = linux_4_core_effective_quantity +
                          linux_8_core_effective_quantity +
                          linux_16_core_effective_quantity +
                          linux_32_core_effective_quantity +
                          linux_64_core_effective_quantity +
                          windows_4_core_effective_quantity +
                          windows_8_core_effective_quantity +
                          windows_16_core_effective_quantity +
                          windows_32_core_effective_quantity +
                          windows_64_core_effective_quantity

    custom_runner_minutes = {
      "ubuntu_4_core" => linux_4_core_effective_quantity,
      "ubuntu_8_core" => linux_8_core_effective_quantity,
      "ubuntu_16_core" => linux_16_core_effective_quantity,
      "ubuntu_32_core" => linux_32_core_effective_quantity,
      "ubuntu_64_core" => linux_64_core_effective_quantity,
      "windows_4_core" => windows_4_core_effective_quantity,
      "windows_8_core" => windows_8_core_effective_quantity,
      "windows_16_core" => windows_16_core_effective_quantity,
      "windows_32_core" => windows_32_core_effective_quantity,
      "windows_64_core" => windows_64_core_effective_quantity,
    }

    macos_12_core_effective_quantity = sku_usage["macos_12_core"][:effective_quantity]
    macos_12_core_total = macos_12_core_effective_quantity
    macos_12_core_minutes = {
      "macos_12_core" => macos_12_core_effective_quantity
    }

    @minutes_used_per_runtime_from_api = standard_minutes.merge(custom_runner_minutes).merge(macos_12_core_minutes)
    @minutes_used_per_runtime_from_api["total"] = total + custom_runner_total + macos_12_core_total
  end
end
