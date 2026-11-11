# typed: strict
# frozen_string_literal: true

class Copilot::LicenseAttributer
  extend T::Helpers

  include Licensing::Licensify
  include GitHub::Memoizer

  sig { params(billable_entity: Billing::Types::OrgOrBusiness).void }
  def initialize(billable_entity)
    @billable_entity = billable_entity
  end

  sig { returns(T.nilable(Integer)) }
  memoize def customer_id
    return nil unless @billable_entity.present?
    ::Licensing::Customer.id_for(@billable_entity)
  end

  sig { returns(Integer) }
  memoize def active_business_count
    filter_grouped_counts(licensify_copilot_grouped_counts, active: true, plan_name: Copilot::SKUIsolation::BUSINESS)
  end

  sig { returns(Integer) }
  memoize def billable_business_count
    filter_grouped_counts(licensify_copilot_grouped_counts, plan_name: Copilot::SKUIsolation::BUSINESS, is_billable: true)
  end

  sig { returns(Integer) }
  memoize def active_enterprise_count
    filter_grouped_counts(licensify_copilot_grouped_counts, active: true, plan_name: Copilot::SKUIsolation::ENTERPRISE)
  end

  sig { returns(Integer) }
  memoize def billable_enterprise_count
    filter_grouped_counts(licensify_copilot_grouped_counts, plan_name: Copilot::SKUIsolation::ENTERPRISE, is_billable: true)
  end

  sig { returns(Integer) }
  def total_active_count
    active_business_count + active_enterprise_count
  end

  sig { returns(Integer) }
  def total_billable_count
    billable_business_count + billable_enterprise_count
  end

  sig { returns(Integer) }
  def business_monthly_cost
    billable_business_count * Copilot::COPILOT_BUSINESS_MONTHLY_BASE_PRICE
  end

  sig { returns(Integer) }
  def enterprise_monthly_cost
    billable_enterprise_count * Copilot::COPILOT_ENTERPRISE_MONTHLY_BASE_PRICE
  end

  sig { returns(Float) }
  def estimated_monthly_cost
    (business_monthly_cost + enterprise_monthly_cost).to_f
  end

  private

  sig { returns(T::Array[::Licensify::Services::V1::GroupedCount]) }
  memoize def licensify_copilot_grouped_counts
    return [] unless customer_id
    get_licensify_grouped_counts(T.must(customer_id), product: Licensing::Licensify::LicensifyProduct::COPILOT)
  end

  sig { returns(T::Hash[String, String]) }
  def licensify_error_tags
    {
      "gh.billing.customer.id": customer_id.to_s,
      "gh.billable_entity.id": @billable_entity.id.to_s,
      "gh.billable_entity.type": @billable_entity.class.name.to_s,
      "licensify.product": "copilot",
    }
  end
end
