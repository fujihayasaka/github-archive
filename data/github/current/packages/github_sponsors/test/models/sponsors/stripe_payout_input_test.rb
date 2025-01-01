# typed: true
# frozen_string_literal: true

require "test_helper"

class SponsorsStripePyoutInputTest < GitHub::TestCase
  test "supports serialization and deserialization to an input value" do
    account_id = "account"
    payout_id = "payout"

    payout  = Sponsors::StripePayoutInput.new(account_id: account_id, payout_id: payout_id)

    assert_equal account_id, payout.account_id
    assert_equal payout_id, payout.payout_id

    hydrated_payout = Sponsors::StripePayoutInput.deserialize(payout.serialize)

    assert_equal account_id, hydrated_payout&.account_id
    assert_equal payout_id, hydrated_payout&.payout_id
  end

  test "deserializes to nil unless both account id and payout id are present" do
    missing_account = Sponsors::StripePayoutInput.new(account_id: "", payout_id: "payout")
    missing_payout = Sponsors::StripePayoutInput.new(account_id: "account", payout_id: "")

    assert_nil Sponsors::StripePayoutInput.deserialize(missing_account.serialize)
    assert_nil Sponsors::StripePayoutInput.deserialize(missing_payout.serialize)
  end
end
