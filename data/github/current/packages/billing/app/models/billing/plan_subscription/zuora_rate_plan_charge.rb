# typed: strict
# frozen_string_literal: true

module Billing
  class PlanSubscription::ZuoraRatePlanCharge < ApplicationRecord::Domain::Billing
    include GitHub::Memoizer

    self.table_name = "zuora_rate_plan_charges"

    belongs_to :plan_subscription, polymorphic: true

    validates :payload, presence: true

    MAX_THROTTLE_RETRIES = 5

    scope :for_self_serve_subscriptions, -> {
      where("plan_subscription_type = 'Billing::PlanSubscription'")
    }

    scope :with_annual_renewal_in_30_days, -> {
      where("charged_through_date = ? AND billing_period = 'Annual'",
        (GitHub::Billing.today + 30.days).to_formatted_s(:db)
      )
    }

    scope :with_price, -> { where("payload->'$.price' > 0") }

    sig do
      params(
        plan_subscription: Billing::Types::Subscription,
        active_charges_from_zuora: T::Array[Billing::Zuora::RatePlanCharge],
        success: T::Boolean
      ).returns(T::Boolean)
    end
    def self.reconcile(plan_subscription:, active_charges_from_zuora:, success: true)
      # success is temporary for logging
      existing_rate_plan_charges = plan_subscription.subscription_rate_plan_charges.to_a
      GitHub.logger.info(
        "code.namespace": self.class.name,
        "code.function": "update_from_zuora_subscription",
        "gh.billing.plan_subscription.id": plan_subscription.id,
        "gh.billing.plan_subscription.zuora_subscription_number": plan_subscription.zuora_subscription_number,
        "gh.billing.plan_subscription.zuora_subscription_id": plan_subscription.zuora_subscription_id,
        "gh.billing.plan_subscription.existing_rate_plan_charges_count": existing_rate_plan_charges.size,
        "gh.billing.plan_subscription.currently_active_rate_plan_charges_count": active_charges_from_zuora.size,
        "gh.billing.plan_subscription.success": success,
      )

      !!throttle_with_retry(max_retry_count: MAX_THROTTLE_RETRIES) do
        Billing::PlanSubscription::ZuoraRatePlanCharge.transaction do
          # Creates or updates payloads for currently active rate plan charges
          active_charges_from_zuora.each do |actual_rate_plan_charge|
            index = existing_rate_plan_charges.find_index do |existing_rate_plan_charge|
              existing_rate_plan_charge.product_rate_plan_charge_id == actual_rate_plan_charge.product_rate_plan_charge_id
            end

            if index
              existing_rate_plan_charge = T.must(existing_rate_plan_charges.delete_at(index))
              payload = actual_rate_plan_charge.to_h
              if existing_rate_plan_charge.payload != payload
                existing_rate_plan_charge.update!(payload: payload)
              end
            else
              plan_subscription.subscription_rate_plan_charges.create!(
                product_rate_plan_charge_id: actual_rate_plan_charge.product_rate_plan_charge_id,
                payload: actual_rate_plan_charge.to_h
              )
            end
          end

          # Destroys records for rate plan charges that are no longer active
          existing_rate_plan_charges.each do |existing_rate_plan_charge|
            existing_rate_plan_charge.destroy!
          end

          true
        end
      end
    end

    delegate :charged_through_date,
      :name,
      :number,
      :price,
      to: :object_from_payload

    delegate_missing_to :object_from_payload

    sig { returns(Billing::Zuora::RatePlanCharge) }
    memoize def object_from_payload
      Billing::Zuora::RatePlanCharge.new(payload)
    end

    sig { returns(T::Hash[String, T::Hash[Symbol, T.untyped]]) }
    def to_serialized_hash
      # TODO: we can remove this once the zuora_rate_plan_charges_table
      # experiment is done
      return {} if number.nil?

      {
        number: number,
        charged_through_date: charged_through_date,
      }
    end
  end
end
