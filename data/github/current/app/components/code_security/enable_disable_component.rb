# typed: strict
# frozen_string_literal: true

class CodeSecurity::EnableDisableComponent < ApplicationComponent
  include SecretScanning::Features::FeatureFlagHelper

  sig { params(repository: Repository, enabled: T::Boolean, update_path: String).void }
  def initialize(repository:, enabled:, update_path:)
    @repository = repository
    @enabled = enabled
    @update_path = update_path
  end

  private

  sig { returns(Repository) }
  attr_reader :repository

  sig { returns(T::Boolean) }
  attr_reader :enabled

  sig { returns(String) }
  attr_reader :update_path

  sig { returns(String) }
  def button_text
    enabled ? "Disable" : "Enable"
  end

  sig { returns(Integer) }
  def input_value
    enabled ? 0 : 1
  end

  sig { returns(T::Boolean) }
  def show_cost_estimate?
    # Only show for Teams
    !repository.advanced_security_products_bundled? &&
      !repository.owner&.business.present?
  end

  sig { returns(T::Hash[Symbol, T.any(Integer, String)]) }
  def cost_breakdown
    result = T.let({}, T::Hash[Symbol, T.any(Integer, String)])
    owner = repository.owner
    return { total: Billing::Money.new(0).format, count: 0 } unless owner

    cost = if increased_license_usage > 0
      owner.advanced_security_price_for_sku(sku: "ghas_code_security_licenses", seats: 1)
    else
      return { total: Billing::Money.new(0).format, count: 0 }
    end

    { per_license_cost: cost.format, count: increased_license_usage, total: (cost * increased_license_usage).format }
  end

  sig { returns(Integer) }
  memoize def increased_license_usage
    owner = repository.owner
    return 0 unless owner

    owner.code_security.seat_usage_increase_if_enabled_for_repo(repository)
  end
end
