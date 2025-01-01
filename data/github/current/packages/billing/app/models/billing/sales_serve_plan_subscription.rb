# typed: true
# frozen_string_literal: true

class Billing::SalesServePlanSubscription < ApplicationRecord::Domain::Billing
  include GitHub::Memoizer

  self.table_name = "billing_sales_serve_plan_subscriptions"

  delegate :business, to: :customer, allow_nil: true

  serialize :zuora_rate_plan_charges, type: Hash
  has_many :subscription_rate_plan_charges, as: :plan_subscription,
    class_name: "Billing::PlanSubscription::ZuoraRatePlanCharge",
    dependent: :destroy

  enum :education_bundle, {
    none:  0,
    essential: 1,
    plus: 2,
  }, prefix: true

  def education_bundle?
    !education_bundle_none?
  end

  belongs_to :customer, touch: true

  validates :customer, presence: true
  validates :zuora_subscription_id, :zuora_subscription_number, presence: true, if: :requires_zuora_references?
  validates :billing_start_date, presence: true

  after_commit :sync_customer_in_billing_platform

  EDUCATION_CHARGE_ID = "2c92a0086a2ea9d5016a32bf801171eb"
  GHEC_FOR_COPILOT_CHARGE_ID = "8a129e0687fb43700187fd9a3efb233d"

  def billable_entity
    business
  end

  def zuora_rate_plan_charge_number(product_rate_plan_charge_id:)
    zuora_rate_plan_charges.dig(product_rate_plan_charge_id, :number)
  end

  sig { returns(T.nilable(Billing::PlanSubscription::ZuoraRatePlanCharge)) }
  memoize def ghe_rate_plan_charge
    subscription_rate_plan_charges.find do |rate_plan_charge|
      next if rate_plan_charge.starts_in_future?

      GitHub.zuora_sales_serve_ghe_product_charge_ids.include?(rate_plan_charge.product_rate_plan_charge_id)
    end
  end

  sig { returns(T.nilable(Billing::PlanSubscription::ZuoraRatePlanCharge)) }
  memoize def ghas_rate_plan_charge
    subscription_rate_plan_charges.find do |rate_plan_charge|
      next if rate_plan_charge.starts_in_future?

      GitHub.zuora_sales_serve_ghas_product_charge_ids.include?(rate_plan_charge.product_rate_plan_charge_id)
    end
  end

  def has_free_usage_product?
    self.zuora_rate_plan_charges.has_key?(EDUCATION_CHARGE_ID)
  end

  def has_ghec_for_copilot?
    self.zuora_rate_plan_charges.has_key?(GHEC_FOR_COPILOT_CHARGE_ID)
  end

  def billed_through_azure_subscription?
    !!business&.billed_through_azure_subscription?
  end

  def clear_external_subscription_references
    success = update(
      zuora_subscription_number: nil,
      zuora_subscription_id: nil,
      zuora_rate_plan_charges: {},
    )

    if success && new_rate_plan_charges_enabled?
      result = Billing::PlanSubscription::ZuoraRatePlanCharge.reconcile(
        plan_subscription: self,
        active_charges_from_zuora: [],
        success: success
      )
      GitHub.dogstats.increment(
        "billing.plan_subscription.charge_clears", tags: ["success:#{!!result}", "sales_serve:true"]
      )
    end

    success
  end

  private

  sig { returns(T::Boolean) }
  def new_rate_plan_charges_enabled?
    flag = :new_zuora_rate_plan_charges
    !!(billable_entity&.feature_enabled?(flag) || GitHub.flipper[flag].enabled?)
  end

  def requires_zuora_references?
    !billed_through_azure_subscription? && zuora_rate_plan_charges.present?
  end

  sig { void }
  def sync_customer_in_billing_platform
    return unless GitHub.billing_enabled?
    customer = self.customer
    return unless customer.present?
    return unless customer.billed_via_billing_platform?

    flag = :sync_billing_platform_customers_on_subscription_changes
    return unless GitHub.flipper[flag].enabled? || billable_entity&.feature_enabled?(flag)

    Billing::UpdateCustomerInBillingPlatformJob.perform_later(customer)
    GitHub.dogstats.increment("plan_subscription.billing_platform_update_customer_called", tags: ["sales_managed:true"])
  end
end
