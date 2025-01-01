# typed: strict
# frozen_string_literal: true

module Billing::Zuora::SalesManagedSubscriptionSynchronizationHelper
  extend T::Sig
  extend T::Helpers

  requires_ancestor { Kernel }

  include GitHub::Memoizer

  class ExistingCustomerError < StandardError; end

  sig(:final) { params(subscription: Billing::Zuora::SalesManagedSubscription).void }
  def initialize(subscription)
    @subscription_number = T.let(subscription.subscription_number, String)
  end

  sig { params(organization: ::Organization).void }
  def sync_data_packs(organization)
    packs = subscription.data_packs
    set_data_packs(organization, packs)
  end

  sig { params(organization: ::Organization, packs: Integer).void }
  def set_data_packs(organization, packs)
    organization.build_asset_status!
    T.must(organization.asset_status).update_data_packs(
      quantity: packs,
      actor: organization,
      force: true,
    )
  end

  sig do
    params(
      customer: ::Customer,
      subscription: Billing::Zuora::SalesManagedSubscription,
      subscription_end_date: Date,
    ).void
  end
  def sync_customer_attributes_without_duplicate(customer, subscription, subscription_end_date)
    account = self.account
    customer_attributes = {
        zuora_account_id: subscription.account_id,
        zuora_account_number: subscription.account_number,
        billing_end_date: subscription_end_date,
        bill_cycle_day: account.bill_cycle_day,
        metered_plan: subscription.metered_ghec?,
    }

    begin
      customer.update!(customer_attributes)
    rescue ActiveRecord::RecordNotUnique
      existing_customer = Customer.find_by(zuora_account_number: subscription.account_number)
      if existing_customer.nil?
        raise ExistingCustomerError.new("Customer not found with Zuora account number")
      end

      existing_customer.update!(zuora_account_number: nil, zuora_account_id: nil)
      updated = customer.update!(customer_attributes)

      GitHub.dogstats.increment("billing.customer_zuora_account_number_conflict.count", tags: [
        "resolved:#{updated}"
      ])
    end

    if account.partner_customer?
      customer.enable_reseller_customer(actor: nil)
    else
      customer.disable_reseller_customer(actor: nil)
    end
  end

  sig { params(number: String).returns(T.nilable(Billing::Zuora::SalesManagedSubscription)) }
  def fetch_latest_subscription(number)
    Billing::Zuora::SalesManagedSubscription.fetch_by_subscription_id(number)
  end

  sig { returns(::Billing::Zuora::Account) }
  memoize def account
    T.must(Billing::Zuora::Account.find(subscription.account_id))
  end

  sig { returns(Billing::Zuora::SalesManagedSubscription) }
  memoize def subscription
    T.must(fetch_latest_subscription(subscription_number))
  end

  sig { returns(String) }
  attr_reader :subscription_number
end
