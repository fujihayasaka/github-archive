# typed: strict
# frozen_string_literal: true

class Billing::Zuora::SalesManagedSubscription
  extend T::Sig

  include GitHub::Memoizer

  MICROSOFT_VSS_SKU_PLAN_NAME = "no_dotcom_plan"

  sig { params(subscription_id: String).returns(T.nilable(T.attached_class)) }
  def self.fetch_by_subscription_id(subscription_id)
    subscription = Zuorest::Model::Subscription.find(subscription_id)
    if subscription[:success]
      new(subscription)
    else
      nil
    end
  end

  sig { params(raw_subscription: Zuorest::Model::Subscription).void }
  def initialize(raw_subscription)
    @raw_subscription = raw_subscription
  end

  sig { returns(T::Boolean) }
  def enterprise?
    raw_subscription[:DotcomEntAccountId__c].present?
  end

  sig { returns(T::Boolean) }
  def organization?
    raw_subscription[:DotcomOrgId__c].present?
  end

  sig { returns(Billing::Types::OrgOrBusiness) }
  memoize def owner
    if enterprise?
      Business.find(raw_subscription[:DotcomEntAccountId__c])
    else
      Organization.find(raw_subscription[:DotcomOrgId__c])
    end
  end

  sig { void }
  def ensure_account_ids_match!
    customer = owner.customer
    if customer && customer.zuora_account_id.present? && customer.zuora_account_id != account_id
      raise Billing::Zuora::WebhookError, "Amendment webhook account id does not match customer account id"
    end
  end

  sig { void }
  def ensure_owner_invoiced!
    if !enterprise? && !owner.invoiced?
      raise Billing::Zuora::WebhookError, "Amendment webhook received for non-invoiced organization"
    end
  end

  sig { returns(String) }
  def id
    raw_subscription[:id]
  end

  sig { returns(String) }
  def account_id
    raw_subscription[:accountId]
  end

  sig { returns(String) }
  def account_number
    raw_subscription[:accountNumber]
  end

  sig { returns(String) }
  def subscription_number
    raw_subscription[:subscriptionNumber]
  end

  sig { returns(T.nilable(Date)) }
  def term_end_date
    if raw_subscription[:termEndDate].present?
      Date.parse(raw_subscription[:termEndDate])
    end
  end

  sig { returns(T.nilable(Date)) }
  def term_start_date
    if raw_subscription[:termStartDate].present?
      Date.parse(raw_subscription[:termStartDate])
    end
  end

  sig { returns(T.nilable(String)) }
  def support_plan
    rate_plan_charges.each do |rate_plan_charge|
      case
      when premium_support_charge?(rate_plan_charge)
        return Configurable::SupportPlan::PREMIUM
      when premium_support_plus_charge?(rate_plan_charge)
        return Configurable::SupportPlan::PREMIUM_PLUS
      when premium_support_plus_msft_charge?(rate_plan_charge)
        return Configurable::SupportPlan::ENGINEERING_DIRECT
      when education_support_charge?(rate_plan_charge)
        return Configurable::SupportPlan::EDUCATION
      else
        next
      end
    end

    nil
  end

  # Public : Determine the number of seats on the subscription
  sig { returns(Integer) }
  memoize def seats
    rate_plan_charges.reduce(0) do |acc, rate_plan_charge|
      if lfs_charge?(rate_plan_charge) || usage_refill_charge?(rate_plan_charge) || microsoft_vss_sku?(rate_plan_charge)
        acc
      else
        acc + rate_plan_charge[:Provisionable_Quantity__c].to_i
      end
    end
  end

  # Public: Given a subscription, determine the plan on the subscription
  sig { returns(T.nilable(String)) }
  def plan
    rate_plan_charges.each do |rate_plan_charge|
      return rate_plan_charge[:Plan_Name__c] if rate_plan_charge[:Plan_Name__c].present?
    end

    nil
  end

  # Public: Returns active rate plan charges
  sig { returns(T::Hash[String, T::Hash[Symbol, String]]) }
  def active_rate_plan_charges
    rate_plan_charges.each_with_object(Hash.new) do |rate_plan_charge, result|
      if rate_plan_charge.active?
        result[rate_plan_charge.product_rate_plan_charge_id] = {
          number: rate_plan_charge.number,
          charged_through_date: rate_plan_charge.charged_through_date
        }
      end
    end
  end

  # Public: Determine the data packs on the subscription
  sig { returns(Integer) }
  memoize def data_packs
    rate_plan_charges.reduce(0) do |acc, rate_plan_charge|
      if lfs_charge?(rate_plan_charge)
        acc + rate_plan_charge.quantity.to_i
      else
        acc
      end
    end
  end

  sig { returns(T::Boolean) }
  def metered_ghec?
    metered_ghec_rate_plan_charge.present?
  end

  sig { returns(T.nilable(Billing::Zuora::RatePlanCharge)) }
  memoize def metered_ghec_rate_plan_charge
    rate_plan_charges.find do |rate_plan_charge|
      rate_plan_charge.is_metered__c?
    end
  end

  # Public: Returns an array of the prepaid usage refill rate plan charges
  sig { returns(T::Array[Billing::Zuora::RatePlanCharge]) }
  memoize def active_usage_refill_rate_plan_charges
    rate_plan_charges.select do |rate_plan_charge|
      usage_refill_charge?(rate_plan_charge) &&
        rate_plan_charge.price.present? &&
        rate_plan_charge.active?
    end
  end

  sig { returns(T.nilable(Billing::Zuora::RatePlanCharge)) }
  memoize def sales_serve_actions_rate_plan_charge
    rate_plan_charges.find do |rate_plan_charge|
      sales_serve_actions_charge?(rate_plan_charge)
    end
  end

  sig { returns(T::Boolean) }
  def has_education_bundle?
    education_bundle_rate_plan_charge.present?
  end

  sig { returns(T.nilable(Billing::Zuora::RatePlanCharge)) }
  memoize def education_bundle_rate_plan_charge
    rate_plan_charges.find do |rate_plan|
      rate_plan.bundle_plan.present? &&
        Billing::SalesServePlanSubscription.education_bundles.keys.include?(rate_plan.bundle_plan)
    end
  end

  # Public: Returns the first active GHE charge
  sig { returns(T.nilable(Billing::Zuora::RatePlanCharge)) }
  memoize def ghe_rate_plan_charge
    rate_plan_charges.reverse_each.find do |rate_plan_charge|
      sales_serve_ghe_charge?(rate_plan_charge) && !rate_plan_charge.starts_in_future?
    end
  end

  # Public: Returns the first active GHAS charge
  sig { returns(T.nilable(Billing::Zuora::RatePlanCharge)) }
  memoize def ghas_rate_plan_charge
    rate_plan_charges.reverse_each.find do |rate_plan_charge|
      sales_serve_ghas_charge?(rate_plan_charge) && !rate_plan_charge.starts_in_future?
    end
  end

  sig { returns(T::Array[Billing::Zuora::RatePlanCharge]) }
  memoize def rate_plan_charges
    raw_subscription.rate_plans.flat_map do |rate_plan|
      rate_plan.rate_plan_charges.map do |rate_plan_charge|
        Billing::Zuora::RatePlanCharge.for(rate_plan_charge.body)
      end
    end
  end

  private

  sig { returns(Zuorest::Model::Subscription) }
  attr_reader :raw_subscription

  # Private: Given a RatePlanCharge, determines if the charge is for premium support.
  sig { params(rate_plan_charge: Billing::Zuora::RatePlanCharge).returns(T::Boolean) }
  def premium_support_charge?(rate_plan_charge)
    GitHub.zuora_github_premium_support_charge_ids.include?(rate_plan_charge.product_rate_plan_charge_id)
  end

  # Private: Given a RatePlanCharge, determines if the charge is for premium support plus.
  sig { params(rate_plan_charge: Billing::Zuora::RatePlanCharge).returns(T::Boolean) }
  def premium_support_plus_charge?(rate_plan_charge)
    GitHub.zuora_github_premium_support_plus_charge_ids.include?(rate_plan_charge.product_rate_plan_charge_id)
  end

  # Private: Given a RatePlanCharge, determines if the charge is for premium support plus - msft.
  sig { params(rate_plan_charge: Billing::Zuora::RatePlanCharge).returns(T::Boolean) }
  def premium_support_plus_msft_charge?(rate_plan_charge)
    GitHub.zuora_github_premium_support_plus_msft_charge_ids.include?(rate_plan_charge.product_rate_plan_charge_id)
  end

  # Private: Given a RatePlanCharge, determines if the charge is for education support.
  sig { params(rate_plan_charge: Billing::Zuora::RatePlanCharge).returns(T::Boolean) }
  def education_support_charge?(rate_plan_charge)
    GitHub.zuora_github_enterprise_campus_program_charge_ids.include?(rate_plan_charge.product_rate_plan_charge_id)
  end

  # Private: Given a RatePlanCharge, determines if the charge is for LFS packs.
  sig { params(rate_plan_charge: Billing::Zuora::RatePlanCharge).returns(T::Boolean) }
  def lfs_charge?(rate_plan_charge)
    GitHub.zuora_lfs_rate_plan_charge_ids.include?(rate_plan_charge.product_rate_plan_charge_id)
  end

  # Private: Given a RatePlanCharge, determines if the charge is for Sales Serve Actions usage.
  sig { params(rate_plan_charge: Billing::Zuora::RatePlanCharge).returns(T::Boolean) }
  def sales_serve_actions_charge?(rate_plan_charge)
    GitHub.zuora_sales_serve_actions_product_charge_ids.include? \
      rate_plan_charge.product_rate_plan_charge_id
  end

  # Internal: Given a RatePlanCharge, determines if the charge is for usage refills.
  sig { params(rate_plan_charge: Billing::Zuora::RatePlanCharge).returns(T::Boolean) }
  def usage_refill_charge?(rate_plan_charge)
    GitHub.zuora_metered_refill_rate_plan_charge_ids.include?(rate_plan_charge.product_rate_plan_charge_id)
  end

  # Private: Given a RatePlanCharge, determines if the charge is for GHE.
  sig { params(rate_plan_charge: Billing::Zuora::RatePlanCharge).returns(T::Boolean) }
  def sales_serve_ghe_charge?(rate_plan_charge)
    GitHub.zuora_sales_serve_ghe_product_charge_ids.include?(rate_plan_charge.product_rate_plan_charge_id)
  end

  # Private: Given a RatePlanCharge, determines if the charge is for GHE.
  sig { params(rate_plan_charge: Billing::Zuora::RatePlanCharge).returns(T::Boolean) }
  def sales_serve_ghas_charge?(rate_plan_charge)
    GitHub.zuora_sales_serve_ghas_product_charge_ids.include?(rate_plan_charge.product_rate_plan_charge_id)
  end

  sig { params(rate_plan_charge: Billing::Zuora::RatePlanCharge).returns(T::Boolean) }
  def microsoft_vss_sku?(rate_plan_charge)
    rate_plan_charge[:Plan_Name__c] == MICROSOFT_VSS_SKU_PLAN_NAME
  end
end
