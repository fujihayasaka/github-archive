# typed: strict
# frozen_string_literal: true

module Billing
  class YearlyCycleNotice
    BATCH_SIZE = 100

    # Sends a yearly billing notice to all accounts with a yearly subscription that will renew in 30 days
    sig { void }
    def self.run
      charges = Billing::PlanSubscription::ZuoraRatePlanCharge
        .for_self_serve_subscriptions
        .with_annual_renewal_in_30_days
        .with_price
      charges.find_in_batches(batch_size: BATCH_SIZE) do |batch|
        prefill_associations_for_charges(batch)
        batch.each do |charge|
          send_yearly_billing_notice(charge)
        end
      end
    end

    sig { params(charges: T::Array[Billing::PlanSubscription::ZuoraRatePlanCharge]).void }
    def self.prefill_associations_for_charges(charges)
      GitHub::PrefillAssociations.prefill_associations(charges, { plan_subscription: [:user, { customer: [:business, :payment_method] }] })
    end

    # Sends a yearly billing notice to the account associated with the provided charge
    sig { params(charge: Billing::PlanSubscription::ZuoraRatePlanCharge).void }
    def self.send_yearly_billing_notice(charge)
      plan_subscription = T.let(charge.plan_subscription, T.nilable(Billing::PlanSubscription))
      if plan_subscription.nil?
        GitHub.logger.warn("Plan subscription not found", logger_fields(charge))
        GitHub.dogstats.increment("billing.yearly_cycle_notice", tags: ["success:false", "reason:missing_plan_subscription"])
        return
      end

      billable_entity = T.let(plan_subscription.billable_entity, T.nilable(Billing::Types::Account))
      if billable_entity.nil?
        GitHub.logger.warn("Billable entity not found", logger_fields(charge, plan_subscription:))
        GitHub.dogstats.increment("billing.yearly_cycle_notice", tags: ["success:false", "reason:missing_billable_entity"])
        return
      end

      # If no payment method is present, the account won't be charged so we shouldn't send a notice
      unless billable_entity.has_valid_payment_method?(feature_type: :noncommercial)
        GitHub.logger.info("Payment method not found", logger_fields(charge, plan_subscription:, billable_entity:))
        GitHub.dogstats.increment("billing.yearly_cycle_notice", tags: ["success:true", "reason:missing_payment_method"])
        return
      end

      # If the expected payment amount for the next cycle is zero, we shouldn't send a notice
      if billable_entity.pending_cycle.payment_amount&.zero?
        GitHub.logger.info("Payment amount is zero", logger_fields(charge, plan_subscription:, billable_entity:))
        GitHub.dogstats.increment("billing.yearly_cycle_notice", tags: ["success:true", "reason:payment_amount_is_zero"])
        return
      end

      # Accounts may have multiple annual subscriptions renewing on the same day, so we need to ensure we only send one notice
      billable_entity_type = billable_entity.class.name
      key = "yearly-billing-notice_#{billable_entity_type}_#{billable_entity.id}"
      if Billing::Kv.store.get(key).value { nil }.present?
        GitHub.logger.info("Notice already sent", logger_fields(charge, plan_subscription:, billable_entity:))
        GitHub.dogstats.increment("billing.yearly_cycle_notice", tags: ["success:true", "reason:notice_already_sent"])
        return
      end

      BillingNotificationsMailer.yearly_billing_notice(billable_entity, charge.charged_through_date).deliver_later

      ActiveRecord::Base.connected_to(role: :writing) do
        Billing::Kv.store.set(key, Time.now.to_s, expires: 6.hours.from_now)
      end

      GitHub.logger.info("Sent yearly billing notice", logger_fields(charge, plan_subscription:, billable_entity:))
      GitHub.dogstats.increment("billing.yearly_cycle_notice", tags: ["success:true"])
    rescue StandardError => error # rubocop:todo Lint/RescueException
      # Rescue all errors here to ensure a single failure doesn't prevent other notices from being sent
      Failbot.report(error)
      GitHub.logger.error(error, logger_fields(charge, plan_subscription:, billable_entity:))
      GitHub.dogstats.increment("billing.yearly_cycle_notice", tags: ["success:false", "reason:#{error.class.name}"])
    end

    sig do
      params(
        charge: Billing::PlanSubscription::ZuoraRatePlanCharge,
        plan_subscription: T.nilable(Billing::PlanSubscription),
        billable_entity: T.nilable(Billing::Types::Account)
      ).returns(T::Hash[String, T.untyped])
    end
    def self.logger_fields(charge, plan_subscription: nil, billable_entity: nil)
      coupon = billable_entity&.coupon
      {
        "code.namespace": self.class.name,
        "code.function": "send_yearly_billing_notice",
        "gh.billing.plan_subscription.id": plan_subscription&.id,
        "gh.billing.plan_subscription.zuora_subscription_number": plan_subscription&.zuora_subscription_number,
        "gh.billing.plan_subscription.zuora_subscription_id": plan_subscription&.zuora_subscription_id,
        "gh.billing.billable_entity.id": billable_entity&.id,
        "gh.billing.billable_entity.billed_on": billable_entity&.billed_on,
        "gh.billing.billable_entity.payment_amount": billable_entity&.payment_amount,
        "gh.billing.billable_entity.pending_cycle.payment_amount": billable_entity&.pending_cycle&.payment_amount,
        "gh.billing.billable_entity.pending_cycle.has_changes": billable_entity&.pending_cycle&.has_changes?,
        "gh.billing.billable_entity.pending_cycle.changing_data_packs": billable_entity&.pending_cycle&.changing_data_packs?,
        "gh.billing.billable_entity.pending_cycle.changing_duration": billable_entity&.pending_cycle&.changing_duration?,
        "gh.billing.billable_entity.pending_cycle.changing_plan": billable_entity&.pending_cycle&.changing_plan?,
        "gh.billing.billable_entity.pending_cycle.changing_seats": billable_entity&.pending_cycle&.changing_seats?,
        "gh.billing.billable_entity.plan_name": billable_entity&.plan&.name,
        "gh.billing.billable_entity.type": billable_entity.class.name,
        "gh.billing.coupon.code": coupon&.code,
        "gh.billing.coupon.discount": coupon&.discount,
        "gh.billing.zuora_rate_plan_charge.id": charge.id,
        "gh.billing.zuora_rate_plan_charge.product_rate_plan_charge_id": charge.product_rate_plan_charge_id,
        "gh.billing.zuora_rate_plan_charge.charged_through_date": charge.charged_through_date,
        "gh.billing.zuora_rate_plan_charge.billing_period": charge.billing_period,
        "gh.billing.zuora_rate_plan_charge.name": charge.name,
        "gh.billing.zuora_rate_plan_charge.price": charge.price,
      }
    end
  end
end
