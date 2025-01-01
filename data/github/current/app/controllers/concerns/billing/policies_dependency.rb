# typed: strict
# frozen_string_literal: true

module Billing::PoliciesDependency
  extend T::Helpers

  include Billing::UsageDependency

  requires_ancestor { ApplicationController }

  abstract!

  sig { params(this_entity: ::Billing::Types::Account, overage_policy_type: String, overage_policy_name: String, overage_policy_enabled: String).returns(T::Boolean) }
  def update_policy_request(this_entity:, overage_policy_type:, overage_policy_name:, overage_policy_enabled:)
    customer = T.must(this_entity.customer)

    overage_policy = {
      type: overage_policy_type,
      name: overage_policy_name,
      enabled: ActiveModel::Type::Boolean.new.cast(overage_policy_enabled),
    }

    # Update the overage policy in the billing platform
    begin
      Billing::UpdateCustomerInBillingPlatformJob.perform_now(
        customer,
        nil,
        overage_policy,
      )

      audit_log_payload = {
        actor: current_user,
        customer_id: customer.id.to_s,
        policy_type: overage_policy_type,
        policy_name: overage_policy_name,
        policy_enabled: overage_policy_enabled,
      }

      add_entity_to_payload(entity: this_entity, payload: audit_log_payload)
      GitHub.instrument("billing.overage_policy_updated", audit_log_payload)
      true
    rescue => e # rubocop:todo Lint/RescueException
      Failbot.report(e)
      false
    end
  end
end
