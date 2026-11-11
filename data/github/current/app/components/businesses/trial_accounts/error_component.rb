# typed: true
# frozen_string_literal: true

class Businesses::TrialAccounts::ErrorComponent < ApplicationComponent
  sig { returns(T.any(Business, MultiTenantProvisioningRequest)) }
  attr_reader :entity

  sig { returns(Symbol) }
  attr_reader :field

  sig { params(entity: T.any(Business, MultiTenantProvisioningRequest), field: Symbol).void }
  def initialize(entity:, field:)
    @entity = entity
    @field = field
  end

  private

  sig { returns(T::Boolean) }
  def render?
    entity.errors.include?(field)
  end

  sig { returns(String) }
  def error_message
    error = entity.errors[field].first
    return error if field == :trial_terms
    humanized_attribute = if entity.is_a?(MultiTenantProvisioningRequest)
      MultiTenantProvisioningRequest::HUMANIZED_ATTRIBUTES[field]
    else
      Business::DFD_HUMANIZED_ATTRIBUTES[field]
    end

    "#{humanized_attribute} #{error}"
  end

  sig { returns(String) }
  def field_data_target
    case field
    when :number_of_seats
      "employeesSize"
    when :admin_name
      "billingFullName"
    when :admin_work_email
      "billingEmail"
    else
      field.to_s.camelize(:lower)
    end
  end
end
