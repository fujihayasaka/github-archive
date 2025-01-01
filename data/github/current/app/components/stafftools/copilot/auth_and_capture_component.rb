# typed: strict
# frozen_string_literal: true

class Stafftools::Copilot::AuthAndCaptureComponent < ApplicationComponent
  extend T::Sig

  sig do
    params(
      entity: T.any(::User, ::Organization)
    ).void
  end
  def initialize(entity:)
    @entity = T.let(entity, T.any(::User, ::Organization))
  end

  sig { returns(String) }
  def ineligibility_reason
    unless @entity.payment_method&.credit_card?
      return "Needs credit card"
    end

    if TrustTiers::Tier.for_billable_owner(@entity).tier == 1
      return "Trusted trust tier"
    end

    "Unknown"
  end

  sig { returns(String) }
  def disabled_reason
    if @entity.disabled_reasons
      return @entity.disabled_reasons.join(", ")
    end

    "Unknown"
  end

  sig { returns(T.nilable(String)) }
  memoize def billing_unlockable_reason
    return "Requires manual transactions" if @entity.customer&.requires_manual_transactions?

    nil
  end

  sig { returns(T::Boolean) }
  def last_authorization_declined?
    existing_authorization&.last_status == "processor_declined"
  end

  sig { returns(T.nilable(::Billing::BillingTransaction)) }
  memoize def existing_authorization
    return unless @entity.customer

    ::Billing::BillingTransaction
      .current_authorizations_for_customer(T.must(@entity.customer).id)
      .last # We want to display the most recent authorization
  end
end
