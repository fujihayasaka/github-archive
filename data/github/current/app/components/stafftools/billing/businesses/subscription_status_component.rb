# typed: true
# frozen_string_literal: true

class Stafftools::Billing::Businesses::SubscriptionStatusComponent < ApplicationComponent
  include GitHub::Memoizer
  include PlanHelper
  include Stafftools::BillingHelper

  def initialize(business:)
    @business = business
  end

  private

  attr_reader :business
  delegate :customer, to: :business
  delegate :balance, to: :zuora_subscription

  def account_ids_out_of_sync?
    zuora_subscription && customer.zuora_account_id != zuora_subscription.zuora_account.id
  end

  def customer_type_text
    business.invoiced? ? "Sales Serve" : "Self Serve"
  end

  memoize def zuora_account
    customer.zuora_object_account
  end

  memoize def plan_subscription
    business.invoiced? ? business.sales_serve_plan_subscription : business.plan_subscription
  end

  memoize def zuora_subscription
    Billing::Zuora::Subscription.find plan_subscription&.zuora_subscription_number
  end
end
