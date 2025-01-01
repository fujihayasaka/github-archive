# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::Stripe::Webhooks::AccountUpdatedTest < GitHub::BillingTestCase
  test "calls SyncStripeAccountDetails if stripe account is found" do
    stripe_connect_account = create(:stripe_connect_account, :payouts_disabled, :unverified,
      :charges_disabled, country: nil, billing_country: nil)
    stripe_connect_account_id = stripe_connect_account.stripe_account_id
    webhook = create(
      :stripe_webhook,
      :account_updated,
      object: { id: stripe_connect_account_id },
      account: stripe_connect_account_id,
    )
    event = ::Stripe::Event.construct_from(webhook.payload)
    account_details = event.data.object

    Sponsors::SyncStripeAccountDetails.expects(:call)
      .with(
        stripe_connect_account,
        account_details: account_details
      ).once

    Billing::Stripe::Webhooks::AccountUpdated.perform(webhook)
  end

  test "calls SyncStripeAccountDetails if stripe account was deleted" do
    stripe_connect_account = create(:stripe_connect_account, :payouts_disabled, :deleted, :unverified,
      :charges_disabled, country: nil, billing_country: nil)
    stripe_connect_account_id = stripe_connect_account.stripe_account_id
    webhook = create(
      :stripe_webhook,
      :account_updated,
      object: { id: stripe_connect_account_id },
      account: stripe_connect_account_id,
    )
    event = ::Stripe::Event.construct_from(webhook.payload)
    account_details = event.data.object

    Sponsors::SyncStripeAccountDetails.expects(:call)
      .with(
        stripe_connect_account,
        account_details: account_details
      ).once

    Billing::Stripe::Webhooks::AccountUpdated.perform(webhook)
  end

  test "does not raise when no stripe account is found" do
    webhook = create(
      :stripe_webhook,
      :account_updated,
      object: { id: "acct_1234" },
      account: "does_not_exist",
    )

    Billing::Stripe::Webhooks::AccountUpdated.perform(webhook)
  end

  test "does not raise when Stripe account does not have a Sponsors listing" do
    stripe_connect_account = create(:stripe_connect_account, :deleted)
    stripe_connect_account.sponsors_listing.destroy!

    webhook = create(
      :stripe_webhook,
      :account_updated,
      object: { id: "acct_1234" },
      account: stripe_connect_account.stripe_account_id,
    )

    Billing::Stripe::Webhooks::AccountUpdated.perform(webhook)
  end
end
