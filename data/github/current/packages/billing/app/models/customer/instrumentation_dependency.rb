# typed: strict
# frozen_string_literal: true

module Customer::InstrumentationDependency
  extend T::Helpers

  requires_ancestor { Customer }

  sig { params(reason: T.nilable(Billing::Public::BillingDisabledReasons)).void }
  def track_lock_billing(reason: nil)
    payload = billing_lock_payload
    payload.merge!(lock_reason: reason.serialize) if reason.present?
    GitHub.instrument("billing.lock", payload)
  end

  sig { params(previously_locked_at: T.nilable(ActiveSupport::TimeWithZone), previously_disabled_reasons: T::Set[Billing::Public::BillingDisabledReasons]).void }
  def track_unlock_billing(previously_locked_at: nil, previously_disabled_reasons: Set.new)
    payload = billing_lock_payload
    payload.merge!(previously_locked_at:) if previously_locked_at.present?
    payload.merge!(previously_disabled_reasons:) if previously_disabled_reasons.present?
    GitHub.instrument("billing.unlock", payload)
  end

  private

  sig { returns(T::Hash[Symbol, T.untyped]) }
  def billing_lock_payload
    payload = {
      customer_id: self.id,
    }

    if locked_at = self.locked_at
      payload.merge!(locked_at: locked_at)
    end

    if owner = billable_owner
      payload.merge!({
        :billed_on => owner.billed_on,
        :billing_attempts => owner.billing_attempts,
        :plan => owner.plan.name,
        owner.event_prefix => owner
      })
    end

    payload
  end
end
