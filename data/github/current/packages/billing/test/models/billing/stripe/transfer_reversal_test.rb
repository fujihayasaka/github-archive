# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::Stripe::TransferReversalTestCase < GitHub::BillingTestCase
  include DogstatsTestHelpers
  include GitHub::Billing::CurrencyTestHelper

  test "creates a reversal" do
    VCR.use_cassette("zuora/stripe/single_reverse_transfer") do
      stripe_transfer_id = "tr_1J1J1WEQsq43iHhXtiMzCQdM"
      stripe_refund_id = "re_#{SecureRandom.hex(8)}"
      zuora_refund_id = SecureRandom.hex(16)

      ::Stripe::Transfer.expects(:create_reversal).with do |id, params|
        assert_equal stripe_transfer_id, id

        assert_equal 20_00, params[:amount]

        metadata = params[:metadata]
        assert_equal 10_00, metadata[:payment_amount_reversed]
        assert_equal 10_00, metadata[:match_amount_reversed]
        assert_equal stripe_refund_id, metadata[:stripe_refund_id]
        assert_equal zuora_refund_id, metadata[:zuora_refund_id]
      end

      result = Billing::Stripe::TransferReversal.perform(
        stripe_transfer_id: stripe_transfer_id,
        stripe_refund_id: stripe_refund_id,
        zuora_refund_id: zuora_refund_id,
      )

      assert_predicate result, :success?
      assert_equal "$20.00 reversed for Stripe transfer #{stripe_transfer_id}.", result.message
    end
  end

  test "creates a partial payment reversal" do
    VCR.use_cassette("zuora/stripe/single_partial_reverse_transfer") do
      stripe_transfer_id = "tr_1J2KsVEQsq43iHhX2FLwv1nD"
      stripe_refund_id = "re_#{SecureRandom.hex(8)}"
      zuora_refund_id = SecureRandom.hex(16)

      ::Stripe::Transfer.expects(:create_reversal).with do |id, params|
        assert_equal stripe_transfer_id, id

        assert_equal 10_00, params[:amount]

        metadata = params[:metadata]
        assert_equal 10_00, metadata[:payment_amount_reversed]
        assert_equal 0, metadata[:match_amount_reversed]
        assert_equal stripe_refund_id, metadata[:stripe_refund_id]
        assert_equal zuora_refund_id, metadata[:zuora_refund_id]
      end

      result = Billing::Stripe::TransferReversal.perform(
        stripe_transfer_id: stripe_transfer_id,
        stripe_refund_id: stripe_refund_id,
        zuora_refund_id: zuora_refund_id,
        payment_amount_to_reverse: 1000,
        match_amount_to_reverse: 0,
      )

      assert_predicate result, :success?
      assert_equal "$10.00 reversed for Stripe transfer #{stripe_transfer_id}.", result.message
    end
  end

  test "creates a partial match reversal" do
    VCR.use_cassette("zuora/stripe/single_partial_match_reverse_transfer") do
      stripe_transfer_id = "tr_1J2LBjEQsq43iHhXiTnEvDRZ"
      stripe_refund_id = "re_#{SecureRandom.hex(8)}"
      zuora_refund_id = SecureRandom.hex(16)

      ::Stripe::Transfer.expects(:create_reversal).with do |id, params|
        assert_equal stripe_transfer_id, id

        assert_equal 10_00, params[:amount]

        metadata = params[:metadata]
        assert_equal 0, metadata[:payment_amount_reversed]
        assert_equal 10_00, metadata[:match_amount_reversed]
        assert_equal stripe_refund_id, metadata[:stripe_refund_id]
        assert_equal zuora_refund_id, metadata[:zuora_refund_id]
      end

      result = Billing::Stripe::TransferReversal.perform(
        stripe_transfer_id: stripe_transfer_id,
        stripe_refund_id: stripe_refund_id,
        zuora_refund_id: zuora_refund_id,
        payment_amount_to_reverse: 0,
        match_amount_to_reverse: 1000,
      )

      assert_predicate result, :success?
      assert_equal "$10.00 reversed for Stripe transfer #{stripe_transfer_id}.", result.message
    end
  end

  context "transfer_to parameter" do
    test "adds metadata that indicate this reversal should be re-transferred to another account" do
      listing = create(:sponsors_listing, :approved, :with_stripe_account)
      inactive_stripe_account = create(:stripe_connect_account, :inactive, sponsors_listing: listing)
      payment_amount_usd_cents = 4_00
      match_amount_usd_cents = 2_00
      total_amount_usd_cents = payment_amount_usd_cents + match_amount_usd_cents

      # This implies USD and CAD were 1-1 at the time of initial transfer
      mock_transfer = fake_stripe_transfer(
        payment_amount_in_cents: payment_amount_usd_cents,
        match_amount_in_cents: match_amount_usd_cents,
        destination: inactive_stripe_account.stripe_account_id,
      )

      ::Stripe::Transfer.expects(:retrieve).with(mock_transfer.id).returns(mock_transfer)
      ::Stripe::Transfer.expects(:create_reversal).with(
          mock_transfer.id,
          amount: total_amount_usd_cents,
          metadata: {
            payment_amount_reversed: payment_amount_usd_cents,
            match_amount_reversed: match_amount_usd_cents,
            stripe_refund_id: nil,
            zuora_refund_id: nil,
            sponsors_listing_id: mock_transfer.metadata["sponsors_listing_id"],
            transfer_to: listing.stripe_transfer_account_id
          }
        ).returns(true)

      result = Billing::Stripe::TransferReversal.perform(
        stripe_transfer_id: mock_transfer.id,
        transfer_to: listing.stripe_transfer_account_id
      )

      expected_message = "$6.00 reversed for Stripe transfer tr_transfer. "\
        "Will be re-transferred to #{listing.stripe_transfer_account_id}."

      assert_predicate result, :success?
      assert_equal expected_message, result.message
    end

    test "requires that the referenced account belong to the same maintainer" do
      listing = create(:sponsors_listing, :approved, :with_stripe_account)
      other_listing = create(:sponsors_listing, :approved, :with_stripe_account)

      payment_amount_usd_cents = 4_00
      match_amount_usd_cents = 2_00
      total_amount_usd_cents = payment_amount_usd_cents + match_amount_usd_cents

      mock_transfer = fake_stripe_transfer(
        payment_amount_in_cents: payment_amount_usd_cents,
        match_amount_in_cents: match_amount_usd_cents,
        destination: listing.stripe_transfer_account_id,
      )

      ::Stripe::Transfer.expects(:retrieve).with(mock_transfer.id).returns(mock_transfer)
      ::Stripe::Transfer.expects(:create_reversal).never

      result = Billing::Stripe::TransferReversal.perform(
        stripe_transfer_id: mock_transfer.id,
        transfer_to: other_listing.stripe_transfer_account_id
      )

      expected_message = "Must re-transfer to Stripe account related to the same listing."

      refute_predicate result, :success?
      assert_equal expected_message, result.message
    end

    test "requires the full amount to be re-transferred" do
      listing = create(:sponsors_listing, :approved, :with_stripe_account)
      inactive_stripe_account = create(:stripe_connect_account, :inactive, sponsors_listing: listing)

      payment_amount_usd_cents = 4_00
      total_amount_usd_cents = payment_amount_usd_cents

      mock_transfer = fake_stripe_transfer(
        payment_amount_in_cents: payment_amount_usd_cents,
        match_amount_in_cents: 0,
        destination: inactive_stripe_account.stripe_account_id,
      )

      ::Stripe::Transfer.expects(:retrieve).with(mock_transfer.id).returns(mock_transfer)
      ::Stripe::Transfer.expects(:create_reversal).never

      result = Billing::Stripe::TransferReversal.perform(
        stripe_transfer_id: mock_transfer.id,
        payment_amount_to_reverse: payment_amount_usd_cents - 1_00,
        transfer_to: listing.stripe_transfer_account_id
      )

      expected_message = "Must re-transfer full amount."

      refute_predicate result, :success?
      assert_equal expected_message, result.message
    end
  end

  test "raises if transfer does not exist" do
    VCR.use_cassette("zuora/stripe/single_reverse_transfer_no_longer_exists") do
      stripe_transfer_id = "1ec14105e6b2352219d43aebcf1b4630"
      stripe_refund_id = "re_#{SecureRandom.hex(8)}"
      zuora_refund_id = SecureRandom.hex(16)

      assert_raises Billing::Stripe::TransferReversal::TransferDoesNotExist do
        Billing::Stripe::TransferReversal.perform(
          stripe_transfer_id: stripe_transfer_id,
          stripe_refund_id: stripe_refund_id,
          zuora_refund_id: zuora_refund_id,
        )
      end
    end
  end

  test "returns success if transfer was already fully reversed" do
    VCR.use_cassette("zuora/stripe/single_reverse_transfer_already_fully_reversed") do
      stripe_transfer_id = "tr_1J1J1WEQsq43iHhXtiMzCQdM"
      stripe_refund_id = "re_#{SecureRandom.hex(8)}"
      zuora_refund_id = SecureRandom.hex(16)

      result = Billing::Stripe::TransferReversal.perform(
        stripe_transfer_id: stripe_transfer_id,
        stripe_refund_id: stripe_refund_id,
        zuora_refund_id: zuora_refund_id,
      )

      assert_predicate result, :success?
      expected_message = "Stripe transfer #{stripe_transfer_id} was already fully reversed."
      assert_equal expected_message, result.message
    end
  end

  # See https://github.com/github/sponsors/issues/4026
  test "reverses currency-corrected transfer amount using current conversion rates" do

    setup_currency_exchange

    payment_amount_usd_cents = 4_00
    match_amount_usd_cents = 2_00
    total_amount_usd_cents = payment_amount_usd_cents + match_amount_usd_cents

    # This implies USD and CAD were 1-1 at the time of initial transfer
    mock_transfer = fake_stripe_transfer(
      payment_amount_in_cents: payment_amount_usd_cents,
      match_amount_in_cents: match_amount_usd_cents,
      destination_amount_in_subunits: total_amount_usd_cents,
      destination_currency: "cad",
    )

    stripe_refund_id = "re_#{SecureRandom.hex(8)}"
    zuora_refund_id = SecureRandom.hex(16)

    # In this fictional world, the Canadian dollar has weakened against USD since the initial transfer
    expected_correction_factor = Rational(1, 2)
    Billing::Money.add_rate("USD", "CAD", 2)

    # Due to the weakened currency, ensure we only reverse half of the USD amount which should
    # have the effect of reversing the original 6 CAD transferred.
    ::Stripe::Transfer.expects(:retrieve).with(mock_transfer.id).returns(mock_transfer)
    ::Stripe::Transfer.expects(:create_reversal).with(
        mock_transfer.id,
        amount: (total_amount_usd_cents * expected_correction_factor).to_i,
        metadata: {
          payment_amount_reversed: (payment_amount_usd_cents * expected_correction_factor).to_i,
          match_amount_reversed: (match_amount_usd_cents * expected_correction_factor).to_i,
          stripe_refund_id: stripe_refund_id,
          zuora_refund_id: zuora_refund_id,
          sponsors_listing_id: mock_transfer.metadata["sponsors_listing_id"],
        }
      ).returns(true)

    result = Billing::Stripe::TransferReversal.perform(
      stripe_transfer_id: mock_transfer.id,
      stripe_refund_id: stripe_refund_id,
      zuora_refund_id: zuora_refund_id,
    )

    expected_message = "$3.00 reversed for Stripe transfer #{mock_transfer.id}. Currency-corrected from $6.00."

    assert_predicate result, :success?
    assert_equal expected_message, result.message
  end

  # See https://github.com/github/sponsors/issues/4026
  test "reverses full transfer amount when destination currency strengthens against USD" do

    setup_currency_exchange

    payment_amount_usd_cents = 4_00
    match_amount_usd_cents = 2_00
    total_amount_usd_cents = payment_amount_usd_cents + match_amount_usd_cents

    # This implies USD and CAD were 1-1 at the time of initial transfer
    mock_transfer = fake_stripe_transfer(
      payment_amount_in_cents: payment_amount_usd_cents,
      match_amount_in_cents: match_amount_usd_cents,
      destination_amount_in_subunits: total_amount_usd_cents,
      destination_currency: "cad",
    )

    stripe_refund_id = "re_#{SecureRandom.hex(8)}"
    zuora_refund_id = SecureRandom.hex(16)

    # In this fictional world, the Canadian dollar has strenghtened against USD since the initial transfer
    expected_correction_factor = 1
    Billing::Money.add_rate("USD", "CAD", 0.5)

    # Clamp to reversing the full USD amount. In this case Stripe should only reverse half the CAD amount
    # originally transferred.
    ::Stripe::Transfer.expects(:retrieve).with(mock_transfer.id).returns(mock_transfer)
    ::Stripe::Transfer.expects(:create_reversal).with(
        mock_transfer.id,
        amount: (total_amount_usd_cents * expected_correction_factor).to_i,
        metadata: {
          payment_amount_reversed: (payment_amount_usd_cents * expected_correction_factor).to_i,
          match_amount_reversed: (match_amount_usd_cents * expected_correction_factor).to_i,
          stripe_refund_id: stripe_refund_id,
          zuora_refund_id: zuora_refund_id,
          sponsors_listing_id: mock_transfer.metadata["sponsors_listing_id"],
        }
      ).returns(true)

    result = Billing::Stripe::TransferReversal.perform(
      stripe_transfer_id: mock_transfer.id,
      stripe_refund_id: stripe_refund_id,
      zuora_refund_id: zuora_refund_id,
    )

    expected_message = "$6.00 reversed for Stripe transfer #{mock_transfer.id}."

    assert_predicate result, :success?
    assert_equal expected_message, result.message
  end

  # See https://github.com/github/sponsors/issues/4026
  test "emits currency-correction metrics" do
    setup_currency_exchange

    payment_amount_usd_cents = 10_00
    match_amount_usd_cents = 10_00
    total_amount_usd_cents = payment_amount_usd_cents + match_amount_usd_cents

    payment_amount_to_reverse_usd_cents = 2_00
    match_amount_to_reverse_usd_cents = 4_00
    total_amount_to_reverse_usd_cents = payment_amount_to_reverse_usd_cents + match_amount_to_reverse_usd_cents

    # This implies USD and CAD were 1-1 at the time of initial transfer
    mock_transfer = fake_stripe_transfer(
      payment_amount_in_cents: payment_amount_usd_cents,
      match_amount_in_cents: match_amount_usd_cents,
      destination_amount_in_subunits: total_amount_usd_cents,
      destination_currency: "cad",
    )

    stripe_refund_id = "re_#{SecureRandom.hex(8)}"
    zuora_refund_id = SecureRandom.hex(16)

    # In this fictional world, the Canadian dollar has weakened against USD since the initial transfer
    correction_factor = Rational(1, 3)
    correction_factor_used = correction_factor
    Billing::Money.add_rate("USD", "CAD", 3)

    expected_payment_reversal_amount_in_cents = (payment_amount_to_reverse_usd_cents * correction_factor_used).to_i
    expected_match_reversal_amount_in_cents = (match_amount_to_reverse_usd_cents * correction_factor_used).to_i
    expected_reversal_amount_in_cents = expected_payment_reversal_amount_in_cents + expected_match_reversal_amount_in_cents

    # Due to the weakened currency, ensure we only reverse half of the USD amount which should
    # have the effect of reversing the original 6 CAD transferred.
    ::Stripe::Transfer.expects(:retrieve).with(mock_transfer.id).returns(mock_transfer)
    ::Stripe::Transfer.expects(:create_reversal).with(
        mock_transfer.id,
        amount: expected_reversal_amount_in_cents,
        metadata: {
          payment_amount_reversed: expected_payment_reversal_amount_in_cents,
          match_amount_reversed: expected_match_reversal_amount_in_cents,
          stripe_refund_id: stripe_refund_id,
          zuora_refund_id: zuora_refund_id,
          sponsors_listing_id: mock_transfer.metadata["sponsors_listing_id"],
        }
      ).returns(true)

    result = Billing::Stripe::TransferReversal.perform(
      stripe_transfer_id: mock_transfer.id,
      stripe_refund_id: stripe_refund_id,
      zuora_refund_id: zuora_refund_id,
      payment_amount_to_reverse: payment_amount_to_reverse_usd_cents,
      match_amount_to_reverse: match_amount_to_reverse_usd_cents,
    )

    expected_tags = [
      "enabled:true",
    ]
    assert_dogstats_increment(1, "sponsors.transfer_reversal.currency_correction.count",
      tags: expected_tags,
    )
    assert_dogstats_count_value(
      4_00, # we want to reverse $6, but would correct to reversing $2 due to the currency fluctuation
      "sponsors.transfer_reversal.currency_correction.unrecovered_amount_in_cents",
      tags: expected_tags,
    )
  end

  # Get a mocked ::Stripe::Transfer
  #
  # amount_in_cents - Integer amount in cents (USD) of the transfer
  # destination_amount_in_subunits - Optional Integer transferred amount in subunits of the destination currency,
  #                                  defaults to transfer amount
  # destination_current - Optional String ISO4217 3-letter currency codes lowe-cased, defaults to "usd"
  #
  # Returns a ::Stripe::Transfer
  def fake_stripe_transfer(payment_amount_in_cents:, match_amount_in_cents:,
    destination_amount_in_subunits: nil,
    destination: "acct_destination",
    destination_currency: "usd"
  )
    total_amount_in_cents = payment_amount_in_cents + match_amount_in_cents
    destination_amount_in_subunit = total_amount_in_cents if destination_amount_in_subunits.nil?

    data = {
      "id": "tr_transfer",
      "object": "transfer",
      "amount": total_amount_in_cents,
      "amount_reversed": 0,
      "balance_transaction": "txn_transaction",
      "created": 1623451222,
      "currency": "usd",
      "description": nil,
      "destination": destination,
      "destination_amount": destination_amount_in_subunits,
      "destination_currency": destination_currency,
      "destination_payment": "py_1J1J1WFxJZYbadPlPfZg7ITh",
      "livemode": false,
      "metadata": {
        "payment_amount": payment_amount_in_cents.to_s,
        "match_amount": match_amount_in_cents.to_s,
        "sponsors_listing_id": "42"
      },
      "reversals": {
        "object": "list",
        "data": [],
        "has_more": false,
        "total_count": 0,
        "url": "/v1/transfers/tr_1J1J1WEQsq43iHhXtiMzCQdM/reversals"
      },
      "reversed": false,
      "source_transaction": nil,
      "source_type": "card",
      "transfer_group": "test"
    }
    # HACK HACK HACK, is there a public API for this?
    # This is shamelessly stolen from
    # https://github.com/stripe/stripe-ruby/blob/ded501370d162515c3030911da6fb4cf5ffb3596/lib/stripe/api_resource.rb#L80-L91
    transfer = Stripe::Transfer.new(data["id"], {})
    transfer.send(:initialize_from, data, {})
    transfer
  end
end
