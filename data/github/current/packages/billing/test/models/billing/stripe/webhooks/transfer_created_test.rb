# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::Stripe::Webhooks::TransferCreatedTest < GitHub::BillingTestCase
  include HydroTestHelpers
  test "creates a payment, match, and transfer ledger entries" do
    parent_listing = create(:sponsors_listing, :approved, :fiscal_host, :with_stripe_account)
    fiscal_host_stripe = parent_listing.active_stripe_connect_account
    child_listing = create(:sponsors_listing, :approved, :with_fiscal_host,
      parent_listing: parent_listing)
    zuora_id = "P-0000001"
    billing_transaction = create(:billing_transaction, platform_transaction_id: zuora_id)
    webhook = create(
      :stripe_webhook,
      :transfer_created,
      object: {
        id: "tr_1",
        amount: 25_00,
        destination: fiscal_host_stripe.stripe_account_id,
        transfer_group: zuora_id,
        metadata: {
          payment_amount: 12_50,
          match_amount: 12_50,
          stripe_charge_id: "ch_0000001",
          paypal_id: "paypal_id",
          credit_balance_adjustment_number: "CBA-0123456",
          sponsors_listing_id: child_listing.id,
        },
      },
    )

    assert_difference(-> { fiscal_host_stripe.ledger_entries.count }, 3) do
      Billing::Stripe::Webhooks::TransferCreated.perform(webhook)
    end

    payment_ledger_entry = fiscal_host_stripe.ledger_entries.payment.last
    assert_equal "payment", payment_ledger_entry.transaction_type
    assert_equal(-12_50, payment_ledger_entry.amount_in_subunits)
    assert_equal "USD", payment_ledger_entry.currency_code
    assert_equal billing_transaction, payment_ledger_entry.billing_transaction
    assert_equal zuora_id, payment_ledger_entry.primary_reference_id
    assert_equal child_listing, payment_ledger_entry.sponsors_listing
    assert_equal "ch_0000001", payment_ledger_entry.stripe_charge_id
    assert_equal "paypal_id", payment_ledger_entry.paypal_id
    assert_equal "CBA-0123456", payment_ledger_entry.credit_balance_adjustment_number

    match_ledger_entry = fiscal_host_stripe.ledger_entries.github_match.last
    assert_equal "github_match", match_ledger_entry.transaction_type
    assert_equal(-12_50, match_ledger_entry.amount_in_subunits)
    assert_equal "USD", match_ledger_entry.currency_code
    assert_equal zuora_id, match_ledger_entry.primary_reference_id
    assert_equal billing_transaction, match_ledger_entry.billing_transaction
    assert_nil match_ledger_entry.stripe_charge_id
    assert_nil match_ledger_entry.paypal_id
    assert_nil match_ledger_entry.credit_balance_adjustment_number
    assert_equal child_listing, match_ledger_entry.sponsors_listing

    transfer_ledger_entry = fiscal_host_stripe.ledger_entries.transfer.last
    assert_equal "transfer", transfer_ledger_entry.transaction_type
    assert_equal 25_00, transfer_ledger_entry.amount_in_subunits
    assert_equal "USD", transfer_ledger_entry.currency_code
    assert_equal billing_transaction, transfer_ledger_entry.billing_transaction
    assert_equal "tr_1", transfer_ledger_entry.primary_reference_id
    assert_equal child_listing, transfer_ledger_entry.sponsors_listing
    assert_equal zuora_id, transfer_ledger_entry.zuora_transaction_id
  end

  test "receiving sponsorship increase billing.sponsors.match metric" do
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
    stripe_connect_account = create(:stripe_connect_account)
    webhook = create(
      :stripe_webhook,
      :transfer_created,
      object: {
        id: "tr_1",
        amount: 25_00,
        destination: stripe_connect_account.stripe_account_id,
        transfer_group: "P-0000001",
        metadata: {
          payment_amount: 12_50,
          match_amount: 12_50,
          stripe_charge_id: "ch_0000001",
        },
      },
    )

    assert_difference(-> { stripe_connect_account.ledger_entries.count }, 3) do
      Billing::Stripe::Webhooks::TransferCreated.perform(webhook)
    end

    increments = GitHub.dogstats.increments("billing.sponsors.match")
    assert_equal 1, increments.count
  end

  test "still creates ledger entry if the Stripe account is soft-deleted" do
    stripe_connect_account = create(:stripe_connect_account, :deleted)

    webhook = create(
      :stripe_webhook,
      :transfer_created,
      object: {
        id: "tr_1",
        amount: 25_00,
        destination: stripe_connect_account.stripe_account_id,
        transfer_group: "P-0000001",
        metadata: {
          payment_amount: 12_50,
          match_amount: 12_50,
          stripe_charge_id: "ch_0000001",
        },
      },
    )

    assert_difference(-> { stripe_connect_account.ledger_entries.count }, 3) do
      Billing::Stripe::Webhooks::TransferCreated.perform(webhook)
    end
  end


  test "exceeding match limit sets match_limit_reached_at for listing in metadata" do
    listing = create(:sponsors_listing, :with_stripe_account)
    sponsorable = listing.sponsorable
    stripe_connect_account = listing.active_stripe_connect_account
    webhook = create(
      :stripe_webhook,
      :transfer_created,
      object: {
        id: "tr_1",
        amount: SponsorsListing::MATCHING_LIMIT_AMOUNT_IN_CENTS * 2,
        destination: stripe_connect_account.stripe_account_id,
        transfer_group: "P-0000001",
        metadata: {
          payment_amount: SponsorsListing::MATCHING_LIMIT_AMOUNT_IN_CENTS,
          match_amount: SponsorsListing::MATCHING_LIMIT_AMOUNT_IN_CENTS,
          stripe_charge_id: "ch_0000001",
          sponsors_listing_id: listing.id,
        },
      },
    )
    assert_nil listing.match_limit_reached_at
    Billing::Stripe::Webhooks::TransferCreated.perform(webhook)
    refute_nil listing.reload.match_limit_reached_at
  end

  test "transfer when we previously reached match limit does not send email" do
    listing = create(:sponsors_listing, :with_stripe_account,
                     match_limit_reached_at: 1.day.ago)
    stripe_connect_account = listing.active_stripe_connect_account

    create(:payouts_ledger_entry, :payment,
      stripe_connect_account: stripe_connect_account,
      amount_in_subunits: -SponsorsListing::MATCHING_LIMIT_AMOUNT_IN_CENTS
    )
    create(:payouts_ledger_entry, :github_match,
      stripe_connect_account: stripe_connect_account,
      amount_in_subunits: -SponsorsListing::MATCHING_LIMIT_AMOUNT_IN_CENTS
    )
    create(:payouts_ledger_entry, :transfer,
      stripe_connect_account: stripe_connect_account,
      amount_in_subunits: SponsorsListing::MATCHING_LIMIT_AMOUNT_IN_CENTS * 2
    )

    webhook = create(
      :stripe_webhook,
      :transfer_created,
      object: {
        id: "tr_1",
        amount: 42_00,
        destination: stripe_connect_account.stripe_account_id,
        transfer_group: "P-0000001",
        metadata: {
          payment_amount: 42_00,
          match_amount: "0",
          stripe_charge_id: "ch_0000001",
        },
      },
    )

    SponsorsPrimerMailer.expects(:reached_match_cap).never
    assert_no_changes -> { listing.reload.match_limit_reached_at } do
      Billing::Stripe::Webhooks::TransferCreated.perform(webhook)
    end
  end

  test "not exceeding match limit does not sends email" do
    listing = create(:sponsors_listing, :with_stripe_account)
    sponsorable = listing.sponsorable
    stripe_connect_account = listing.active_stripe_connect_account
    webhook = create(
      :stripe_webhook,
      :transfer_created,
      object: {
        id: "tr_1",
        amount: (SponsorsListing::MATCHING_LIMIT_AMOUNT_IN_CENTS * 2) - 200,
        destination: stripe_connect_account.stripe_account_id,
        transfer_group: "P-0000001",
        metadata: {
          payment_amount: SponsorsListing::MATCHING_LIMIT_AMOUNT_IN_CENTS - 100,
          match_amount: SponsorsListing::MATCHING_LIMIT_AMOUNT_IN_CENTS - 100,
          stripe_charge_id: "ch_0000001",
        },
      },
    )

    assert_nil listing.match_limit_reached_at
    Billing::Stripe::Webhooks::TransferCreated.perform(webhook)
    assert_nil listing.reload.match_limit_reached_at
  end

  test "when zero match do not increase billing.sponsors.match metric" do
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
    stripe_connect_account = create(:stripe_connect_account)
    webhook = create(
      :stripe_webhook,
      :transfer_created,
      object: {
        id: "tr_1",
        amount: 25_00,
        destination: stripe_connect_account.stripe_account_id,
        transfer_group: "P-0000001",
        metadata: {
          payment_amount: 25_00,
          stripe_charge_id: "ch_0000001",
        },
      },
    )

    Billing::Stripe::Webhooks::TransferCreated.perform(webhook)

    increments = GitHub.dogstats.increments("billing.sponsors.match")
    assert_equal 0, increments.count
  end

  test "creates a payment and transfer ledger entries when the payment is not matched" do
    stripe_connect_account = create(:stripe_connect_account)
    webhook = create(
      :stripe_webhook,
      :transfer_created,
      object: {
        id: "tr_1",
        amount: 25_00,
        destination: stripe_connect_account.stripe_account_id,
        transfer_group: "P-0000001",
        metadata: {
          payment_amount: 25_00,
          stripe_charge_id: "ch_0000001",
        },
      },
    )

    assert_difference(-> { stripe_connect_account.ledger_entries.count }, 2) do
      Billing::Stripe::Webhooks::TransferCreated.perform(webhook)
    end

    payment_ledger_entry = stripe_connect_account.ledger_entries.payment.last
    assert_equal "payment", payment_ledger_entry.transaction_type
    assert_equal(-25_00, payment_ledger_entry.amount_in_subunits)
    assert_equal "USD", payment_ledger_entry.currency_code
    assert_equal "P-0000001", payment_ledger_entry.primary_reference_id
    assert_equal "ch_0000001", payment_ledger_entry.stripe_charge_id

    transfer_ledger_entry = stripe_connect_account.ledger_entries.transfer.last
    assert_equal "transfer", transfer_ledger_entry.transaction_type
    assert_equal 25_00, transfer_ledger_entry.amount_in_subunits
    assert_equal "USD", transfer_ledger_entry.currency_code
    assert_equal "tr_1", transfer_ledger_entry.primary_reference_id
    assert_equal "P-0000001", transfer_ledger_entry.zuora_transaction_id
  end

  test "does not put the payouts ledger out of balance" do
    stripe_connect_account = create(:stripe_connect_account)
    webhook = create(
      :stripe_webhook,
      :transfer_created,
      object: {
        id: "tr_1",
        amount: 25_00,
        destination: stripe_connect_account.stripe_account_id,
        transfer_group: "P-0000001",
        metadata: {
          payment_amount: 12_50, # Does not match transfer amount 25_00
          stripe_charge_id: "ch_0000001",
        },
      },
    )

    assert_difference(-> { stripe_connect_account.ledger_entries.count }, 0) do
      assert_raises(ActiveModel::ValidationError, /must balance to zero/) do
        Billing::Stripe::Webhooks::TransferCreated.perform(webhook)
      end
    end
  end

  test "publishes a hydro event with transfer details" do
    subscribe("payout.transfer")
    zuora_id = "2c92c0fa624bb1f20162694a4ebe37bf"
    billing_transaction = create(:billing_transaction, platform_transaction_id: zuora_id)

    stripe_connect_account = create(:stripe_connect_account)
    webhook = create(
      :stripe_webhook,
      :transfer_created,
      object: {
        id: "tr_1",
        amount: 25_00,
        destination: stripe_connect_account.stripe_account_id,
        transfer_group: zuora_id,
        metadata: {
          payment_amount: 12_50,
          match_amount: 12_50,
          stripe_charge_id: "ch_0000001",
        },
      },
    )

    Billing::Stripe::Webhooks::TransferCreated.perform(webhook)

    assert_hydro_published({
      account: Hydro::EntitySerializer.user(billing_transaction.user),
      total_transfer_amount_in_cents: 25_00,
      match_amount_in_cents: 12_50,
      sponsorship_amount_in_cents: 12_50,
      destination_account_type: :STRIPE_CONNECT,
      destination_account_id: stripe_connect_account.stripe_account_id,
      payment_gateway: :STRIPE,
      matched: true,
    }, schema: "github.payouts.v0.Transfer")
  end

  test "creates ledger entries for invoiced sponsorships" do
    stripe_connect_account = create(:stripe_connect_account)
    zuora_id = "2c92a00d6ff0e96f0170168b81415536"
    webhook = create(
      :stripe_webhook,
      :transfer_created,
      object: {
        id: "tr_1",
        amount: 100_00,
        destination: stripe_connect_account.stripe_account_id,
        transfer_group: "2c92a00d6ff0e96f0170168b81415536",
        metadata: {
          payment_amount: 100_00,
          match_amount: 0,
          invoiced_sponsorship_transfer_id: 1,
          sponsor_id: 1,
          actor_id: 1,
        },
      },
    )

    assert_difference(-> { stripe_connect_account.ledger_entries.count }, 2) do
      Billing::Stripe::Webhooks::TransferCreated.perform(webhook)
    end

    payment_ledger_entry = stripe_connect_account.ledger_entries.payment.last
    assert_equal "payment", payment_ledger_entry.transaction_type
    assert_equal(-100_00, payment_ledger_entry.amount_in_subunits)
    assert_equal "USD", payment_ledger_entry.currency_code
    assert_equal zuora_id, payment_ledger_entry.primary_reference_id
    assert_nil payment_ledger_entry.zuora_transaction_id

    transfer_ledger_entry = stripe_connect_account.ledger_entries.transfer.last
    assert_equal "transfer", transfer_ledger_entry.transaction_type
    assert_equal 100_00, transfer_ledger_entry.amount_in_subunits
    assert_equal "USD", transfer_ledger_entry.currency_code
    assert_equal "tr_1", transfer_ledger_entry.primary_reference_id
    assert_equal zuora_id, transfer_ledger_entry.zuora_transaction_id
  end

  test "publishes a hydro event with invoiced transfer details" do
    travel_to "2023-11-14"
    sponsor = create(:invoiced_organization)
    stripe_connect_account = create(:stripe_connect_account)
    zuora_id = "2c92a00d6ff0e96f0170168b81415536"
    webhook = create(
      :stripe_webhook,
      :transfer_created,
      object: {
        id: "tr_1",
        amount: 100_00,
        destination: stripe_connect_account.stripe_account_id,
        transfer_group: "2c92a00d6ff0e96f0170168b81415536",
        metadata: {
          payment_amount: 100_00,
          match_amount: 0,
          invoiced_sponsorship_transfer_id: 1,
          sponsor_id: sponsor.id,
          actor_id: 1,
        },
      },
    )

    Billing::Stripe::Webhooks::TransferCreated.perform(webhook)

    assert_hydro_published({
      account: Hydro::EntitySerializer.user(sponsor),
      total_transfer_amount_in_cents: 100_00,
      match_amount_in_cents: 0,
      sponsorship_amount_in_cents: 100_00,
      destination_account_type: :STRIPE_CONNECT,
      destination_account_id: stripe_connect_account.stripe_account_id,
      payment_gateway: :INVOICE,
      matched: false,
    }, schema: "github.payouts.v0.Transfer")
  end
end
