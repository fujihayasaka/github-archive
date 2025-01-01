# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::Stripe::ManualTransferTestCase < GitHub::BillingTestCase
  fixtures do
    @sponsorable    = create(:user, :sponsorable)
    @listing        = @sponsorable.sponsors_listing
    @stripe_account = create(:stripe_connect_account,
      sponsors_listing: @listing,
      stripe_account_id: "acct_1G61WUJWUR5CcHHA",
    )
  end

  test "create transfer with payment and match amount" do
    VCR.use_cassette("zuora/stripe/manual_transfer") do
      result = Billing::Stripe::ManualTransfer.perform(
        stripe_account_id: @stripe_account.stripe_account_id,
        payment_amount: 500,
        match_amount: 500,
        transfer_group: "_transfer_group_test",
        stripe_charge_id: "_stripe_charge_id_test",
        sponsors_listing_id: @listing.id,
      )

      assert_predicate result, :success?
      assert_equal "$10.00 manual transfer created. Stripe Transfer ID: tr_1JFlgdEQsq43iHhXm3y3AelY", result.message
    end
  end

  test "create transfer with payment amount" do
    VCR.use_cassette("zuora/stripe/manual_transfer_with_payment_amount") do
      result = Billing::Stripe::ManualTransfer.perform(
        stripe_account_id: @stripe_account.stripe_account_id,
        payment_amount: 500,
        match_amount: 0,
        transfer_group: "_transfer_group_test",
        stripe_charge_id: "_stripe_charge_id_test",
        sponsors_listing_id: @listing.id,
      )

      assert_predicate result, :success?
      assert_equal "$5.00 manual transfer created. Stripe Transfer ID: tr_1JFliREQsq43iHhXIAMr3vbz", result.message
    end
  end

  test "create transfer with match amount" do
    VCR.use_cassette("zuora/stripe/manual_transfer_with_match_amount") do
      result = Billing::Stripe::ManualTransfer.perform(
        stripe_account_id: @stripe_account.stripe_account_id,
        payment_amount: 0,
        match_amount: 500,
        transfer_group: "_transfer_group_test",
        stripe_charge_id: "_stripe_charge_id_test",
        sponsors_listing_id: @listing.id,
      )

      assert_predicate result, :success?
      assert_equal "$5.00 manual transfer created. Stripe Transfer ID: tr_1JFliQEQsq43iHhX48xiope6", result.message
    end
  end

  test "validates stripe_account_id presence" do
    result = Billing::Stripe::ManualTransfer.perform(
      stripe_account_id: nil,
      payment_amount: 10,
      match_amount: 0,
      transfer_group: "_transfer_group_test",
      stripe_charge_id: "_stripe_charge_id_test",
      sponsors_listing_id: @listing.id,
    )

    refute_predicate result, :success?
    assert_equal "Must have a Stripe Connect account id.", result.message
  end

  test "validates sponsors_listing_id presence" do
    result = Billing::Stripe::ManualTransfer.perform(
      stripe_account_id: @stripe_account.stripe_account_id,
      payment_amount: 0,
      match_amount: 0,
      transfer_group: "_transfer_group_test",
      stripe_charge_id: "_stripe_charge_id_test",
      sponsors_listing_id: nil,
    )

    refute_predicate result, :success?
    assert_equal "Must have a sponsors listing id.", result.message
  end

  test "does not transfer zero charge" do
    result = Billing::Stripe::ManualTransfer.perform(
      stripe_account_id: @stripe_account.stripe_account_id,
      payment_amount: 0,
      match_amount: 0,
      transfer_group: "_transfer_group_test",
      stripe_charge_id: "_stripe_charge_id_test",
      sponsors_listing_id: @listing.id,
    )

    refute_predicate result, :success?
    assert_equal "Cannot transfer a negative amount of money.", result.message
  end

  test "reports an error if stripe connect account is not found" do
    VCR.use_cassette("zuora/stripe/manual_transfer_with_not_found_account") do
      result = Billing::Stripe::ManualTransfer.perform(
        stripe_account_id: "acct_not_found",
        payment_amount: 500,
        match_amount: 500,
        transfer_group: "_transfer_group_test",
        stripe_charge_id: "_stripe_charge_id_test",
        sponsors_listing_id: @listing.id,
      )

      refute_predicate result, :success?
      assert_equal "No such destination: 'acct_not_found'", result.message
    end
  end

  test "reports an error if stripe connect account has insufficient funds" do
    VCR.use_cassette("zuora/stripe/manual_transfer_without_funds") do
      result = Billing::Stripe::ManualTransfer.perform(
        stripe_account_id: @stripe_account.stripe_account_id,
        payment_amount: 500_00,
        match_amount: 500_00,
        currency: "EUR",
        transfer_group: "_transfer_group_test",
        stripe_charge_id: "_stripe_charge_id_test",
        sponsors_listing_id: @listing.id,
      )

      refute_predicate result, :success?
      assert_match "Insufficient funds in Stripe account", result.message.to_s
    end
  end
end
