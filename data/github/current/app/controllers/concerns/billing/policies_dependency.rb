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

      # Handle CCR Direct Org Billing policy changes when PRU policy changes
      if overage_policy_type == "sku" && overage_policy_name == "copilot_premium_request"
        update_ccr_direct_org_billing_policy_for_pru_change(this_entity, overage_policy[:enabled])
      end

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
    rescue => e
      Failbot.report(e)
      false
    end
  end

  private

  sig { params(entity: ::Billing::Types::Account, pru_enabled: T::Boolean).void }
  def update_ccr_direct_org_billing_policy_for_pru_change(entity, pru_enabled)
    return unless entity.is_a?(::Business)

    copilot_business = Copilot::Business.new(entity)

    if pru_enabled
      # When PRU is enabled, set CCR Direct Org Billing to no_policy only if CCR is no_policy
      ccr_value = copilot_business.configuration.code_review
      if ccr_value == "no_policy"
        Copilot::Policies::CcrDirectOrgBilling.update_business(copilot_business, "no_policy")
      end
    else
      # When PRU is disabled, always disable CCR Direct Org Billing
      Copilot::Policies::CcrDirectOrgBilling.update_business(copilot_business, "disabled")
    end
  rescue => e
    # Don't fail the overage policy update if this cascade fails
    Failbot.report(e)
  end
end
