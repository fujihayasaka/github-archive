# typed: strict
# frozen_string_literal: true

class Billing::Zuora::PrepaidMeteredUsageRefillSynchronizer
  extend T::Sig

  sig { params(subscription: Billing::Zuora::SalesManagedSubscription, expires_on: Date).void }
  def initialize(subscription, expires_on)
    @subscription = subscription
    @expires_on = expires_on
  end

  # Public: Determine the prepaid usage refills on the subscription and create refills on new subscription
  #
  sig { void }
  def synchronize!
    refill_was_created = T.let(false, T::Boolean)

    subscription.active_usage_refill_rate_plan_charges.each do |rate_plan_charge|
      if !Billing::PrepaidMeteredUsageRefill.exists?(zuora_rate_plan_charge_number: rate_plan_charge[:number])
        Billing::PrepaidMeteredUsageRefillCreator.new(
          owner: subscription.owner,
          zuora_rate_plan_charge_id: rate_plan_charge[:id],
          zuora_rate_plan_charge_number: rate_plan_charge[:number],
          expires_on: expires_on,
          amount_in_subunits: rate_plan_charge[:price] * rate_plan_charge[:quantity] * 100,
          currency_code: rate_plan_charge[:currency],
        ).create!

        refill_was_created = true
      end
    end

    reset_depleted_prepaid_credits_notices if refill_was_created
  end

  private

  sig { returns(Billing::Zuora::SalesManagedSubscription) }
  attr_reader :subscription
  sig { returns(Date) }
  attr_reader :expires_on

  sig { void }
  def reset_depleted_prepaid_credits_notices
    ::Billing::ResetNoticesJob.perform_later("depleted_prepaid_credits", subscription.owner)
  end
end
