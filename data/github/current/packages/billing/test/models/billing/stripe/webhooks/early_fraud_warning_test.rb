# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::Stripe::Webhooks::EarlyFraudWarningTest < GitHub::BillingTestCase
  include HydroTestHelpers

  test "publishes hydro event with an early fraud warning's details" do
    fraud_id = "issfr_1"
    stripe_account_id = "acct_1234"
    billing_transaction = create(:billing_transaction, transaction_id: "ch_1234")

    # Create a new early_fraud_warning webhook. The object data is sourced from
    # test/fixtures/billing/stripe/events/early_fraud_warning.json. Include object in order to
    # override the default fraud object data in the json file.
    webhook = create(
      :stripe_webhook,
      :radar_early_fraud_warning_created,
      object: {
        id: fraud_id,
        charge: "ch_1234",
      },
      account: stripe_account_id,
    )

    Billing::Stripe::Webhooks::EarlyFraudWarning.perform(webhook)

    assert_hydro_published({
      stripe_fraud_id: fraud_id,
      actionable: true,
      stripe_charge_id: "ch_1234",
      fraud_type: :MISC,
      stripe_timestamp: Time.at(123456789).to_datetime,
      user_id: billing_transaction.user_id,
    }, schema: "github.billing.v0.EarlyFraudWarning")
  end

  test "publishes additional Sponsors-specific hydro event if charge includes sponsorships" do
    stripe_charge_id = "ch_1234"
    stripe_connect_account = create(:stripe_connect_account)
    create(:payouts_ledger_entry, :payment,
      sponsors_listing: stripe_connect_account.sponsors_listing,
      stripe_connect_account: stripe_connect_account,
      stripe_charge_id: stripe_charge_id
    )
    fraud_id = "issfr_1"
    create(:billing_transaction, transaction_id: stripe_charge_id)

    # Create a new early_fraud_warning webhook. The object data is sourced from
    # test/fixtures/billing/stripe/events/early_fraud_warning.json. Include object in order to
    # override the default fraud object data in the json file.
    webhook = create(
      :stripe_webhook,
      :radar_early_fraud_warning_created,
      object: {
        id: fraud_id,
        charge: stripe_charge_id,
      },
      account: "acct_1234",
    )

    Billing::Stripe::Webhooks::EarlyFraudWarning.perform(webhook)

    assert_hydro_messages(count: 1, schema: "github.billing.v0.EarlyFraudWarning")
    assert_hydro_messages(count: 1, schema: "github.sponsors.v1.EarlyFraudWarning")
  end

  test "does not publish hydro event if early_fraud_warning event is a test payload" do
    create(:stripe_connect_account)
    stripe_charge_id = "ch_1234"
    create(:billing_transaction, transaction_id: stripe_charge_id)
    webhook = create(
      :stripe_webhook,
      :radar_early_fraud_warning_created,
      object: {
        charge: stripe_charge_id,
        livemode: false,
      },
    )

    Billing::Stripe::Webhooks::EarlyFraudWarning.perform(webhook)

    refute_hydro_messages(schema: "github.billing.v0.EarlyFraudWarning")
  end
end
