# typed: true
# frozen_string_literal: true

require "test_helper"

class SponsorsEmitEarlyFraudWarningTest < GitHub::TestCase
  include HydroTestHelpers

  fixtures do
    @sponsor = create(:verified_user)
    @listing_with_stripe = create(:sponsors_listing, :approved, :with_stripe_account)
  end

  test "does not emit Hydro event if no related Sponsors payment exists" do
    event = {
      stripe_fraud_id: "issfr_1",
      actionable: true,
      stripe_charge_id: "ch_1",
      stripe_timestamp: Time.at(123456789).to_datetime,
      fraud_type: :MISC,
      user_id: nil,
    }

    result = Sponsors::EmitEarlyFraudWarning.call(event)

    assert_equal false, result
    refute_hydro_messages(schema: "github.sponsors.v1.EarlyFraudWarning")
  end

  test "emits Hydro event if related Sponsors payment found" do
    stripe_charge_id = "ch_1"

    stripe_account = @listing_with_stripe.active_stripe_connect_account
    create(:payouts_ledger_entry, :payment,
      sponsors_listing: @listing_with_stripe,
      stripe_connect_account: stripe_account,
      stripe_charge_id: stripe_charge_id
    )

    event = {
      stripe_fraud_id: "issfr_1",
      actionable: true,
      stripe_charge_id: stripe_charge_id,
      stripe_timestamp: Time.at(123456789).to_datetime,
      fraud_type: :MISC,
      user_id: @sponsor.id,
    }

    result = Sponsors::EmitEarlyFraudWarning.call(event)

    assert_equal true, result

    emitted = hydro_messages(schema: "github.sponsors.v1.EarlyFraudWarning")

    assert_equal 1, emitted.count, "expected one Hydro message for this schema"
    message = emitted.first

    assert_equal "issfr_1", message[:stripe_fraud_id]
    assert_equal true, message[:actionable]
    assert_equal stripe_charge_id, message[:stripe_charge_id]
    assert_equal :MISC, message[:fraud_type]
    assert_equal 123456789, message[:stripe_timestamp][:seconds]
    assert_equal @listing_with_stripe.stripe_transfer_account_id, message[:stripe_account_id]
    assert_equal @listing_with_stripe.id, message[:sponsors_listing][:id]
    assert_equal @listing_with_stripe.sponsorable_id, message[:sponsorable][:id]
    assert_equal @listing_with_stripe.id, message[:sponsors_listing_stafftools_metadata][:sponsors_listing_id]
    assert_equal @sponsor.id, message[:sponsor][:id]
    assert_equal Hydro::EntitySerializer.stripe_connect_account(stripe_account), message[:stripe_connect_account]
  end

  test "emits multiple Hydro events if multiple Sponsors payments exist" do
    stripe_charge_id = "ch_1"

    create(:payouts_ledger_entry, :payment,
      sponsors_listing: @listing_with_stripe,
      stripe_connect_account: @listing_with_stripe.active_stripe_connect_account,
      stripe_charge_id: stripe_charge_id
    )

    other_listing = create(:sponsors_listing, :approved, :with_stripe_account)
    create(:payouts_ledger_entry, :payment,
      sponsors_listing: other_listing,
      stripe_connect_account: other_listing.active_stripe_connect_account,
      stripe_charge_id: stripe_charge_id
    )

    event = {
      stripe_fraud_id: "issfr_1",
      actionable: true,
      stripe_charge_id: stripe_charge_id,
      stripe_timestamp: Time.at(123456789).to_datetime,
      fraud_type: :MISC,
      user_id: @sponsor.id,
    }

    result = Sponsors::EmitEarlyFraudWarning.call(event)

    assert_equal true, result

    assert_hydro_messages(count: 2, schema: "github.sponsors.v1.EarlyFraudWarning")
  end
end
