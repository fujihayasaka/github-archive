# typed: strict
# frozen_string_literal: true

class Billing::Zuora::RatePlan
  extend T::Sig

  include GitHub::Memoizer

  delegate :[], to: :raw_rate_plan

  sig { returns(T::Array[Billing::Zuora::RatePlanCharge]) }
  attr_accessor :rate_plan_charges

  sig { params(rate_plan_hash: T::Hash[T.any(Symbol, String), T.untyped]).void }
  def initialize(rate_plan_hash)
    @raw_rate_plan = T.let(rate_plan_hash.with_indifferent_access, HashWithIndifferentAccess)
    @rate_plan_charges = T.let(build_rate_plan_charges, T::Array[Billing::Zuora::RatePlanCharge])
  end

  sig { returns(String) }
  def id
    raw_rate_plan[:id]
  end

  sig { returns(T.nilable(Integer)) }
  memoize def subscription_item_id
    id = rate_plan_charges.pick(Billing::Zuora::RatePlanCharge::SUBSCRIPTION_ITEM_ID_FIELD)
    id.present? ? id.to_i : nil
  end

  sig { returns(T::Boolean) }
  def active?
    !scheduled_for_removal? && rate_plan_charges.any?(&:active?)
  end

  sig { returns(T::Boolean) }
  def inactive?
    !active?
  end

  sig { returns(T::Boolean) }
  def one_time_plan?
    rate_plan_charges.any?(&:one_time?)
  end

  sig { returns(T::Boolean) }
  def scheduled_for_removal?
    raw_rate_plan[:lastChangeType] == "Remove"
  end

  sig { returns(String) }
  def name
    raw_rate_plan[:ratePlanName]
  end

  sig { returns(String) }
  def product_id
    raw_rate_plan[:productId]
  end

  sig { returns(String) }
  def product_name
    raw_rate_plan[:productName]
  end

  sig { returns(String) }
  def product_rate_plan_id
    raw_rate_plan[:productRatePlanId]
  end

  sig { returns(String) }
  def product_sku
    raw_rate_plan[:productSku]
  end

  # Public: Does this Zuora rate plan correspond to the candidate rate plan generated from GitHub data?
  #
  # Used during synchronization to find a matching rate plan for addition/update/removal
  #
  # candidate_rate_plan - Hash generated from GitHub data reflecting desired rate plan.
  # org_id_by_sub_item_id_mapping - Hash { Integer -> Integer } used to check org ids of rate plans.
  #
  # Returns a Boolean.
  sig do
    params(
      candidate_rate_plan: T::Hash[Symbol, T.untyped],
      org_id_by_sub_item_id_mapping: T::Hash[Integer, Integer]
    )
    .returns(T::Boolean)
  end
  def matches_candidate?(candidate_rate_plan, org_id_by_sub_item_id_mapping)
    return false if product_rate_plan_id != candidate_rate_plan[:productRatePlanId]
    active_sub_item_id = subscription_item_id
    return true unless active_sub_item_id # if sub items are untracked, we assume the product rate plan is sufficient
    sub_item_id_field = Billing::Zuora::RatePlanCharge::SUBSCRIPTION_ITEM_ID_FIELD.to_sym
    candidate_sub_item_id = candidate_rate_plan[:chargeOverrides].pick(sub_item_id_field).to_i
    # There's subtlety here! We need to be sensitive to the fact that candidate and active rate plans tracking
    # different subscription items might still be related. This is the case for e.g. sponsorships where the
    # cancellation of one subscription item and activation of another represents a Zuora update when the
    # subscription item is related to the same sponsoring organization. Said another way this ensures that
    # any given organization can only have one active product rate plan, but multiple organizations can each have
    # their own active product rate plan in the case of self-serve enterprise accounts.
    candidate_org_id = org_id_by_sub_item_id_mapping[candidate_sub_item_id]
    active_org_id = org_id_by_sub_item_id_mapping[active_sub_item_id]
    if candidate_org_id
      candidate_org_id == active_org_id
    else
      candidate_sub_item_id == active_sub_item_id
    end
  end

  private

  sig { returns(HashWithIndifferentAccess) }
  attr_reader :raw_rate_plan

  sig { returns(T::Array[Billing::Zuora::RatePlanCharge]) }
  def build_rate_plan_charges
    return [] if raw_rate_plan[:ratePlanCharges].nil?

    raw_rate_plan[:ratePlanCharges].map do |rate_plan_charge_hash|
      Billing::Zuora::RatePlanCharge.for(rate_plan_charge_hash)
    end
  end
end
