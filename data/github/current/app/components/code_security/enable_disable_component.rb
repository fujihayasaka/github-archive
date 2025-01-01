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

  # Only show this license increase, as a bullet item, if the repo
  # is part of an enterprise
  sig { returns(T::Boolean) }
  memoize def show_license_increase?
    @repository.owner&.business.present?
  end

  sig { returns(T::Boolean) }
  memoize def show_cost_breakdown?
    owner = @repository.owner
    return false unless owner
    return false unless owner.organization?
    return false unless T.cast(owner, ::Organization).advanced_security_purchased_for_entity?

    # Only show for Teams
    return false if @repository.owner&.business.present?

    # Must be unbundled
    return false if repository.advanced_security_products_bundled?

    # This component is only used for the Code Security SKU, so we can
    # assume that the appropriate products are purchased
    true
  end

  sig { returns(T::Hash[Symbol, T.any(Integer, String)]) }
  memoize def cost_breakdown
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

  sig { returns(T::Boolean) }
  memoize def enablement_blocked?
    ::CodeSecurity::Features::AdvancedSecurityHelper.code_security_metered_usage_locked?(repository: repository)
  end

  # Only shown to team orgs since they see a cost breakdown that includes a monetary amount
  sig { returns(T::Boolean) }
  memoize def show_trial_banner?
    return false unless code_security_trial

    T.must(code_security_trial).enabled?
  end

  sig { returns(T.nilable(Billing::Types::OrgOrBusiness)) }
  memoize def billable_entity
    owner = @repository.owner
    return nil unless owner

    billable_entity = owner.advanced_security_billable_entity
    return nil unless billable_entity

    billable_entity
  end

  sig { returns(String) }
  memoize def entity_type
    case billable_entity
    when ::Organization
      "organization"
    when ::Business
      "business"
    else
      ""
    end
  end

  sig { returns(T.nilable(EnterpriseCloudOnboard::CodeSecurityTrial)) }
  memoize def code_security_trial
    return nil unless billable_entity

    EnterpriseCloudOnboard::CodeSecurityTrial.new(billable_entity: T.must(billable_entity))
  end
end
