# typed: strict
# frozen_string_literal: true

class Billing::Zuora::RatePlanCharge
  include GitHub::Memoizer

  SUBSCRIPTION_ITEM_ID_FIELD = "Subscription_Item_Id__c"

  sig { params(rate_plan_charge_hash: T::Hash[Symbol, T.untyped]).returns(T.any(Billing::Zuora::OneTimeCharge, Billing::Zuora::RatePlanCharge)) }
  def self.for(rate_plan_charge_hash)
    return Billing::Zuora::OneTimeCharge.new(rate_plan_charge_hash) if rate_plan_charge_hash[:type] == "OneTime"

    self.new(rate_plan_charge_hash)
  end

  delegate :[], to: :raw_rate_plan_charge

  sig { params(rate_plan_charge_hash: T::Hash[T.any(Symbol, String), T.untyped]).void }
  def initialize(rate_plan_charge_hash)
    @raw_rate_plan_charge = T.let(rate_plan_charge_hash.with_indifferent_access, HashWithIndifferentAccess)
  end

  sig { returns(String) }
  def id
    raw_rate_plan_charge[:id]
  end

  sig { returns(String) }
  def name
    raw_rate_plan_charge[:name]
  end

  sig { returns(T::Boolean) }
  def active?
    effective_end_date = self.effective_end_date
    effective_end_date.blank? || effective_end_date > GitHub::Billing.today
  end

  sig { returns(T::Boolean) }
  def inactive?
    !active?
  end

  sig { returns(T::Boolean) }
  def starts_in_future?
    if effective_start_date = self.effective_start_date
      return GitHub::Billing.future?(effective_start_date)
    end
    false
  end

  sig { returns(T.nilable(Integer)) }
  def subscription_item_id
    raw_rate_plan_charge[SUBSCRIPTION_ITEM_ID_FIELD.to_sym]
  end

  sig { returns(T::Boolean) }
  def annual?
    billing_period == "Annual"
  end

  sig { returns(T::Boolean) }
  def one_time?
    raw_rate_plan_charge[:type] == "OneTime"
  end

  sig { returns(T::Boolean) }
  def usage?
    raw_rate_plan_charge[:type] == "Usage"
  end

  sig { returns(T.nilable(Date)) }
  memoize def effective_start_date
    return if raw_rate_plan_charge[:effectiveStartDate].blank?

    Date.parse(raw_rate_plan_charge[:effectiveStartDate])
  end

  sig { returns(T.nilable(Date)) }
  memoize def effective_end_date
    return if raw_rate_plan_charge[:effectiveEndDate].blank?

    Date.parse(raw_rate_plan_charge[:effectiveEndDate])
  end

  sig { returns(T.nilable(Date)) }
  memoize def processed_through_date
    return if raw_rate_plan_charge[:processedThroughDate].blank?

    Date.parse(raw_rate_plan_charge[:processedThroughDate])
  end

  sig { returns(T.nilable(Date)) }
  memoize def charged_through_date
    return if raw_rate_plan_charge[:chargedThroughDate].blank?

    Date.parse(raw_rate_plan_charge[:chargedThroughDate])
  end

  sig { returns(String) }
  def product_rate_plan_charge_id
    raw_rate_plan_charge[:productRatePlanChargeId]
  end

  sig { returns(String) }
  def number
    raw_rate_plan_charge[:number]
  end

  sig { returns(String) }
  def billing_period
    raw_rate_plan_charge[:billingPeriod]
  end

  sig { returns(T.nilable(Billing::Types::NonMoneyNumeric)) }
  def price
    raw_rate_plan_charge[:price]
  end

  sig { returns(T.nilable(Billing::Types::NonMoneyNumeric)) }
  def included_units
    raw_rate_plan_charge[:includedUnits]
  end

  sig { returns(T.nilable(String)) }
  def bundle_plan
    raw_rate_plan_charge[:BundlePlan__c]&.downcase
  end

  sig { returns(T::Boolean) }
  def is_metered__c?
    raw_rate_plan_charge[:IsMetered__c].to_s.downcase == "true"
  end

  sig { returns(T.nilable(Float)) }
  def discount_percentage
    raw_rate_plan_charge[:discountPercentage]
  end

  sig { returns(T.nilable(Float)) }
  def discount_amount
    raw_rate_plan_charge[:discountAmount]
  end

  sig { returns(T.any(Float, Integer)) }
  def quantity
    raw_rate_plan_charge[:quantity]
  end

  sig { returns(T::Hash[String, T.untyped]) }
  def to_h
    raw_rate_plan_charge.stringify_keys
  end

  private

  sig { returns(HashWithIndifferentAccess) }
  attr_reader :raw_rate_plan_charge
end
