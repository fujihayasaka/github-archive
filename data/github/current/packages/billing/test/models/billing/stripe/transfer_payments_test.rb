# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::Stripe::TransferPaymentsTestCase < GitHub::BillingTestCase
  include GitHub::Billing::CurrencyTestHelper
  include HydroTestHelpers

  setup do
    setup_currency_exchange
  end

  test "transfers paypal payments" do
    VCR.use_cassette("zuora/stripe/paypal_payment") do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

      stripe_connect_account_id = "acct_1Ep35IFxJZYbadPl"
      sponsors_tier = create(:sponsors_tier, :approved_sponsors_listing)
      listing = sponsors_tier.listing
      stripe_connect_account = create(:stripe_connect_account,
        stripe_account_id: stripe_connect_account_id, sponsors_listing: listing)
      sponsorship_record = create(:sponsorship,
        sponsorable: listing.sponsorable,
        tier: sponsors_tier,
      )
      line_item = create(:billing_transaction_line_item,
        subscribable: sponsors_tier,
        billing_transaction: create(:billing_transaction, user: sponsorship_record.sponsor),
        amount_in_cents: 2_00,
      )

      paypal_id = "paypal_id"
      zuora_payment = Zuorest::Model::Payment.new(
        "Id" => "2c92c0fb61f9c8910161fde1a9e552ca",
        "Gateway" => "Paypal",
        "GatewayState" => "Settled",
        "GatewayResponse" => "Approved",
        "PaymentMethodSnapshotId" => "2c92c0fb61f9c8910161fde1a9e552ca",
        "GatewayResponseCode" => "200",
        "ReferenceId" => paypal_id,
      )
      payment = Billing::Zuora::Payment.new(zuora_payment)

      Stripe::Transfer.expects(:create).once.with do |transfer|
        assert_equal 2_00, transfer[:amount]
        assert_equal "usd", transfer[:currency]
        assert_equal stripe_connect_account_id, transfer[:destination]
        assert_equal zuora_payment.id, transfer[:transfer_group]

        metadata = transfer[:metadata]
        assert_equal 2_00, metadata[:payment_amount]
        assert_equal 0, metadata[:match_amount]
        assert_nil metadata[:stripe_charge_id]
        assert_equal paypal_id, metadata[:paypal_id]
        assert_equal listing.id, metadata[:sponsors_listing_id]
      end

      Billing::Stripe::TransferPayments.perform([line_item], payment)

      charge_not_found = GitHub.dogstats.increments("stripe.charge.not_found")
      transfer_failed = GitHub.dogstats.increments("stripe.transfer.failed")

      # If there were no errors, we assume success
      assert_equal 0, charge_not_found.count
      assert_equal 0, transfer_failed.count
    end
  end

  test "reports an error if stripe connect account is not found" do
    VCR.use_cassette("zuora/stripe/connect_account_not_found") do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

      stripe_connect_account_id = "no_account"
      line_item = create(:billing_transaction_line_item, :sponsors, :with_sponsorship)
      stripe_connect_account = create(:stripe_connect_account,
        stripe_account_id: stripe_connect_account_id,
        sponsors_listing: line_item.sponsors_listing)

      stripe_transaction_id = "ch_1EfTT6EQsq43iHhXJTYv2P8m"
      zuora_payment = Zuorest::Model::Payment.new(
        "Id" => "2c92c0fb61f9c8910161fde1a9e552ca",
        "Gateway" => Billing::Zuora::PaymentGateway::STRIPE_V2,
        "GatewayResponse" => "Approved",
        "GatewayResponseCode" => "200",
        "ReferenceId" => stripe_transaction_id,
      )
      payment = Billing::Zuora::Payment.new(zuora_payment)

      Billing::Stripe::TransferPayments.perform([line_item], payment)

      increments = GitHub.dogstats.increments("stripe.transfer.failed")

      assert_equal 1, increments.count
    end
  end

  test "does not transfer zero charge sponsors line items" do
    sponsors_listing = create(:sponsors_listing, :approved, :with_stripe_account)
    line_item = create(
      :billing_transaction_line_item,
      subscribable: sponsors_listing.default_tier,
      amount_in_cents: 0
    )

    zuora_payment = Zuorest::Model::Payment.new(
      "Gateway" => Billing::Zuora::PaymentGateway::STRIPE_V2,
      "GatewayResponse" => "Approved",
      "GatewayResponseCode" => "200",
      "ReferenceId" => "stripe_id",
    )
    payment = Billing::Zuora::Payment.new(zuora_payment)

    Stripe::Transfer.expects(:create).never

    Billing::Stripe::TransferPayments.perform([line_item], payment)
  end

  test "does not transfer line items representing sponsors fees" do
    sponsors_listing = create(:sponsors_listing, :approved, :with_stripe_account)
    line_item = create(
      :billing_transaction_line_item,
      :sponsors_fee,
      subscribable: sponsors_listing.default_tier,
      amount_in_cents: 100
    )

    zuora_payment = Zuorest::Model::Payment.new(
      "Gateway" => Billing::Zuora::PaymentGateway::STRIPE_V2,
      "GatewayResponse" => "Approved",
      "GatewayResponseCode" => "200",
      "ReferenceId" => "stripe_id",
    )
    payment = Billing::Zuora::Payment.new(zuora_payment)

    Stripe::Transfer.expects(:create).never

    Billing::Stripe::TransferPayments.perform([line_item], payment)
  end

  test "transfers only non-fee line items when there are both fees and non-fees" do
    sponsors_listing = create(:sponsors_listing, :approved, :with_stripe_account)
    line_item = create(
      :billing_transaction_line_item,
      :sponsors_fee,
      subscribable: sponsors_listing.default_tier,
      amount_in_cents: 100
    ) # fee, should not be transferred
    line_item2 = create(
      :billing_transaction_line_item,
      subscribable: sponsors_listing.default_tier,
      amount_in_cents: 200
    ) # non-fee, should be transferred

    zuora_payment = Zuorest::Model::Payment.new(
      "Id" => "2c92c0fb61f9c8910161fde1a9e552ca",
      "Gateway" => Billing::Zuora::PaymentGateway::STRIPE_V2,
      "GatewayResponse" => "Approved",
      "GatewayResponseCode" => "200",
      "ReferenceId" => "stripe_id",
    )
    payment = Billing::Zuora::Payment.new(zuora_payment)

    Stripe::Transfer.expects(:create).once.with do |transfer|
      assert_equal 200, transfer[:amount]
      assert_equal 200, transfer.dig(:metadata, :payment_amount)
      assert_equal sponsors_listing.id, transfer.dig(:metadata, :sponsors_listing_id)
    end

    Billing::Stripe::TransferPayments.perform([line_item, line_item2], payment)
  end

  test "transfers net amount with multiple line items for the same listing" do
    sponsors_listing = create(:sponsors_listing, :approved, :with_stripe_account, tier_count: 2)
    tier1, tier2 = sponsors_listing.sponsors_tiers
    line_item1 = create(:billing_transaction_line_item, :sponsors, subscribable: tier1, amount_in_cents: -100)
    line_item2 = create(:billing_transaction_line_item, :sponsors, subscribable: tier2, amount_in_cents: 1100)

    zuora_payment = Zuorest::Model::Payment.new(
      "Id" => "2c92c0fb61f9c8910161fde1a9e552ca",
      "Gateway" => Billing::Zuora::PaymentGateway::STRIPE_V2,
      "GatewayResponse" => "Approved",
      "GatewayResponseCode" => "200",
      "ReferenceId" => "stripe_id",
    )
    payment = Billing::Zuora::Payment.new(zuora_payment)

    Stripe::Transfer.expects(:create).once.with do |transfer|
      assert_equal 1000, transfer[:amount]
      assert_equal 1000, transfer.dig(:metadata, :payment_amount)
      assert_equal sponsors_listing.id, transfer.dig(:metadata, :sponsors_listing_id)
    end

    Billing::Stripe::TransferPayments.perform([line_item1, line_item2], payment)
  end

  test "transfers payments to the associated stripe connect account" do
    VCR.use_cassette("zuora/stripe/transfer_payment") do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

      stripe_connect_account_id = "acct_1Ep35IFxJZYbadPl"
      sponsors_tier = create(:sponsors_tier, :approved_sponsors_listing)
      stripe_connect_account = create(:stripe_connect_account,
        stripe_account_id: stripe_connect_account_id, sponsors_listing: sponsors_tier.listing)
      line_item = create(:billing_transaction_line_item, subscribable: sponsors_tier)

      stripe_transaction_id = "ch_1Ep2HZEQsq43iHhXnN43Gk9U"
      zuora_payment = Zuorest::Model::Payment.new(
        "Id" => "2c92c0fb61f9c8910161fde1a9e552ca",
        "Gateway" => Billing::Zuora::PaymentGateway::STRIPE_V2,
        "GatewayResponse" => "Approved",
        "GatewayResponseCode" => "200",
        "ReferenceId" => stripe_transaction_id,
      )
      payment = Billing::Zuora::Payment.new(zuora_payment)

      Billing::Stripe::TransferPayments.perform([line_item], payment)

      charge_not_found = GitHub.dogstats.increments("stripe.charge.not_found")
      transfer_failed = GitHub.dogstats.increments("stripe.transfer.failed")

      # If there were no errors, we assume success
      assert_equal 0, charge_not_found.count
      assert_equal 0, transfer_failed.count
    end
  end

  test "uses the fiscal host's Stripe account for a child listing" do
    fiscal_host_listing = create(:sponsors_listing, :fiscal_host)
    fiscal_host_stripe = create(:stripe_connect_account, sponsors_listing: fiscal_host_listing)
    child_listing = create(:sponsors_listing, :approved, :with_fiscal_host, :with_tier,
      parent_listing: fiscal_host_listing)
    sponsorship = create(:sponsorship, sponsorable: child_listing.sponsorable,
      tier: child_listing.default_tier)
    amount_in_cents = child_listing.default_tier.monthly_price_in_cents
    line_item = create(:billing_transaction_line_item,
      subscribable: child_listing.default_tier,
      billing_transaction: create(:billing_transaction, user: sponsorship.sponsor),
      amount_in_cents: amount_in_cents,
    )
    payment = Billing::Zuora::Payment.new(Zuorest::Model::Payment.new(
      "Gateway" => Billing::Zuora::PaymentGateway::STRIPE_V2,
      "GatewayResponse" => "Approved",
      "GatewayResponseCode" => "200",
      "Id" => "8675309",
      "ReferenceId" => "ch_some_stripe_id",
    ))
    expected_metadata = {
      payment_amount: amount_in_cents,
      match_amount: 0,
      stripe_charge_id: "ch_some_stripe_id",
      sponsors_listing_id: child_listing.id,
    }

    Stripe::Transfer.expects(:create).once.with do |transfer|
      assert_equal "usd", transfer[:currency]
      assert_equal fiscal_host_stripe.stripe_account_id, transfer[:destination]
      assert_equal "8675309", transfer[:transfer_group]
      assert_equal expected_metadata, transfer[:metadata]
    end

    Billing::Stripe::TransferPayments.perform([line_item], payment)
  end

  test "sends the necessary parameters and metadata with a matched transfer" do
    date_within_match_deadline = SponsorsListing::JOINED_WAITLIST_MATCH_DEADLINE - 2.days

    stripe_transaction_id = "ch_1Ep2HZEQsq43iHhXnN43Gk9U"
    stripe_connect_account_id = "acct_1Ep35IFxJZYbadPl"

    time = 2.months.ago
    sponsors_tier = travel_to(time) { create(:sponsors_tier, :approved_sponsors_listing) }
    listing = sponsors_tier.listing
    listing.update!(joined_at: date_within_match_deadline)

    payment_amount_in_cents = 2_00
    match_amount_in_cents = 2_00
    expected_metadata = {
      payment_amount: payment_amount_in_cents,
      match_amount: match_amount_in_cents,
      stripe_charge_id: stripe_transaction_id,
      sponsors_listing_id: listing.id,
    }

    VCR.use_cassette("zuora/stripe/transfer_payment") do
      line_item = travel_to(time) do
        stripe_connect_account = create(:stripe_connect_account,
          stripe_account_id: stripe_connect_account_id,
          sponsors_listing: listing)
        sponsorship_record = create(:sponsorship,
          sponsorable: listing.sponsorable,
          tier: sponsors_tier,
        )
        create(
          :billing_transaction_line_item,
          subscribable: sponsors_tier,
          billing_transaction: create(:billing_transaction, user: sponsorship_record.sponsor),
          amount_in_cents: payment_amount_in_cents,
        )
      end
      zuora_payment = Zuorest::Model::Payment.new(
        "Gateway" => Billing::Zuora::PaymentGateway::STRIPE_V2,
        "GatewayResponse" => "Approved",
        "GatewayResponseCode" => "200",
        "Id" => "2000000456789",
        "ReferenceId" => stripe_transaction_id,
      )
      payment = Billing::Zuora::Payment.new(zuora_payment)

      Stripe::Transfer.expects(:create).once.with do |transfer|
        assert_equal payment_amount_in_cents + match_amount_in_cents, transfer[:amount]
        assert_equal "usd", transfer[:currency]
        assert_equal stripe_connect_account_id, transfer[:destination]
        assert_equal zuora_payment.id, transfer[:transfer_group]

        assert_equal expected_metadata, transfer[:metadata]
      end

      Billing::Stripe::TransferPayments.perform([line_item], payment)
    end
  end

  test "does not attempt transfer if listing plan has no stripe connect account" do
    VCR.use_cassette("zuora/stripe/transfer_payment") do
      sponsors_tier = create(:sponsors_tier, :approved_sponsors_listing)
      line_item = create(:billing_transaction_line_item, subscribable: sponsors_tier)

      stripe_transaction_id = "ch_1Ep2HZEQsq43iHhXnN43Gk9U"
      zuora_payment = Zuorest::Model::Payment.new(
        "Gateway" => Billing::Zuora::PaymentGateway::STRIPE_V2,
        "GatewayResponse" => "Approved",
        "GatewayResponseCode" => "200",
        "ReferenceId" => stripe_transaction_id,
      )
      payment = Billing::Zuora::Payment.new(zuora_payment)

      Stripe::Transfer.expects(:create).never

      Billing::Stripe::TransferPayments.perform([line_item], payment)
    end
  end

  test "failed stripe transfer triggers Hydro Event" do
    VCR.use_cassette("zuora/stripe/paypal_payment") do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

      stripe_connect_account_id = "acct_1Ep35IFxJZYbadPl"
      sponsors_tier = create(:sponsors_tier, :approved_sponsors_listing)
      listing = sponsors_tier.listing
      stripe_connect_account = create(:stripe_connect_account,
        stripe_account_id: stripe_connect_account_id, sponsors_listing: listing)
      sponsorship_record = create(:sponsorship,
        sponsorable: listing.sponsorable,
        tier: sponsors_tier,
      )
      line_item = create(:billing_transaction_line_item,
        subscribable: sponsors_tier,
        billing_transaction: create(:billing_transaction, user: sponsorship_record.sponsor),
        amount_in_cents: 2_00,
      )

      paypal_id = "paypal_id"
      zuora_payment = Zuorest::Model::Payment.new(
        "Id" => "2c92c0fb61f9c8910161fde1a9e552ca",
        "Gateway" => "Paypal",
        "GatewayState" => "Settled",
        "GatewayResponse" => "Approved",
        "PaymentMethodSnapshotId" => "2c92c0fb61f9c8910161fde1a9e552ca",
        "GatewayResponseCode" => "200",
        "ReferenceId" => paypal_id,
      )
      payment = Billing::Zuora::Payment.new(zuora_payment)

      Stripe::Transfer.expects(:create).once.raises(Stripe::InvalidRequestError.new("failed", nil))

      Billing::Stripe::TransferPayments.perform([line_item], payment)

      increments = GitHub.dogstats.increments("stripe.transfer.failed")
      assert_equal 1, increments.count

      message = hydro_messages(schema: "github.sponsors.v1.SponsorshipTransferFailure").first
      assert_equal "failed", message[:reason]
      assert_equal line_item.amount_in_cents, message[:amount_in_cents]
      assert_equal line_item.sponsors_listing.id, message[:listing][:id]
      assert_equal line_item.sponsorship.id, message[:sponsorship][:id]
      assert_equal line_item.sponsors_stripe_transfer_account_id, message[:stripe_account_id]
      assert_equal line_item.billing_transaction_id, message[:billing_transaction_id]
      assert_equal Hydro::EntitySerializer.stripe_connect_account(stripe_connect_account),
        message[:stripe_connect_account]
    end
  end
end
