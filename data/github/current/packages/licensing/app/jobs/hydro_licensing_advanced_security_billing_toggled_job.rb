# typed: strict
# frozen_string_literal: true

class HydroLicensingAdvancedSecurityBillingToggledJob < HydroMessageJob
  include GitHub::Memoizer

  queue_as :hydro_licensing_advanced_security_billing_toggled
  retry_on_dirty_exit

  sig { void }
  def perform
    customer_id = extract_customer_id
    return unless customer_id
    UpdateCustomerInLicensifyJob.perform_later(customer_id)
  end

  protected

  sig { override.returns(T::Hash[String, T.untyped]) }
  def logging_context
    super.merge({
      "gh.customer.id" => extract_customer_id,
      "gh.licensing.billable_entity.type" => billable_entity_type,
      "gh.licensing.billable_entity.id" => extract_billable_entity&.id,
    })
  end

  private

  sig { returns(T.nilable(Integer)) }
  memoize def extract_customer_id
    billable_entity = extract_billable_entity
    return nil unless billable_entity

    Licensing::Customer.id_for(billable_entity)
  end

  sig { returns(T.nilable(T.any(::Organization, ::Business))) }
  memoize def extract_billable_entity
    if message[:organization]
      organization_data = message[:organization]
      organization_id = organization_data[:id]
      return nil unless organization_id

      ::Organization.find_by(id: organization_id)
    elsif message[:business]
      business_data = message[:business]
      business_id = business_data[:id]
      return nil unless business_id

      ::Business.find_by(id: business_id)
    end
  end

  sig { returns(T.nilable(String)) }
  memoize def billable_entity_type
    return "organization" if message[:organization]
    return "business" if message[:business]
    nil
  end
end
