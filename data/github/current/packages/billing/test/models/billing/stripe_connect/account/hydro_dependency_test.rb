# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::StripeConnect::Account::HydroDependencyTest < GitHub::TestCase
  include HydroTestHelpers

  context "#hydro_verification_status" do
    test "returns a symbol for the account's valid verification status" do
      {
        UNKNOWN: :unknown,
        UNVERIFIED_REQUIREMENTS_PAST_DUE: :unverified_requirements_past_due,
        UNVERIFIED_REQUIREMENTS_CURRENTLY_DUE: :unverified_requirements_currently_due,
        UNVERIFIED_DETAILS_NOT_SUBMITTED: :unverified_details_not_submitted,
        UNVERIFIED_NO_TRANSFERS_CAPABILITY: :unverified_no_transfers_capability,
        UNVERIFIED_NO_TAX_REPORTING_CAPABILITY: :unverified_no_tax_reporting_capability,
        UNVERIFIED_NO_CARD_PAYMENTS_CAPABILITY: :unverified_no_card_payments_capability,
        UNVERIFIED: :unverified,
        VERIFIED: :verified,
      }.each do |expected, verification_status|
        account = Billing::StripeConnect::Account.new(verification_status: verification_status)
        assert_equal expected, account.hydro_verification_status
      end
    end
  end

  context "#hydro_payout_interval" do
    test "returns a symbol for the account's valid payout interval" do
      {
        MANUAL: :manual,
        DAILY: :daily,
        WEEKLY: :weekly,
        MONTHLY: :monthly,
      }.each do |expected, payout_interval|
        account = Billing::StripeConnect::Account.new(payout_interval: payout_interval)
        assert_equal expected, account.hydro_payout_interval
      end
    end

    test "returns :UNKNOWN_PAYOUT_INTERVAL when the payout interval is unexpected" do
      account = Billing::StripeConnect::Account.new(payout_interval: :fortnightly)
      assert_equal :UNKNOWN_PAYOUT_INTERVAL, account.hydro_payout_interval
    end
  end
end
