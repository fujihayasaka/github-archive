# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::Stripe::Webhooks::TransferReversedTest < GitHub::BillingTestCase
  include HydroTestHelpers

  test "does nothing if reversal has already been recorded" do
    listing = create(:sponsors_listing, :approved, :with_stripe_account)
    stripe_account = listing.active_stripe_connect_account
    webhook = create(
      :stripe_webhook,
      :transfer_reversed,
      object: {
        id: "tr_00000000000000",
        amount: 25_00,
        destination: stripe_account.stripe_account_id,
        transfer_group: "P-0000001",
        metadata: {
          payment_amount: 12_50,
          match_amount: 12_50,
          stripe_charge_id: "ch_0000001",
          paypal_id: "paypal_id",
          credit_balance_adjustment_number: "CBA-0123456",
          sponsors_listing_id: listing.id,
        },
        reversals: {
          object: "list",
          data: [
            {
              id: "trr_00000000000000",
              amount: 25_00,
              transfer: "tr_00000000000000",
              source_refund: nil,
              currency: "usd",
              metadata: {
                payment_amount_reversed: 12_50,
                match_amount_reversed: 12_50,
                stripe_refund_id: "re_00000000000000",
                zuora_refund_id: "R-0000001",
                sponsors_listing_id: listing.id,
              },
            },
          ],
        },
      },
    )

    create(:payouts_ledger_entry, :transfer_reversal,
      stripe_connect_account: stripe_account,
      primary_reference_id: "trr_00000000000000"
    )

    assert_difference(-> { stripe_account.ledger_entries.count }, 0) do
      Billing::Stripe::Webhooks::TransferReversed.perform(webhook)
    end
  end

  test "for a transfer with one reversal" do
    parent_listing = create(:sponsors_listing, :approved, :fiscal_host, :with_stripe_account)
    fiscal_host_stripe = parent_listing.active_stripe_connect_account
    child_listing = create(:sponsors_listing, :approved, :with_fiscal_host,
      parent_listing: parent_listing)
    webhook = create(
      :stripe_webhook,
      :transfer_reversed,
      object: {
        id: "tr_00000000000000",
        amount: 25_00,
        destination: fiscal_host_stripe.stripe_account_id,
        transfer_group: "P-0000001",
        metadata: {
          payment_amount: 12_50,
          match_amount: 12_50,
          stripe_charge_id: "ch_0000001",
          paypal_id: "paypal_id",
          credit_balance_adjustment_number: "CBA-0123456",
          sponsors_listing_id: child_listing.id,
        },
        reversals: {
          object: "list",
          data: [
            {
              id: "trr_00000000000000",
              amount: 25_00,
              transfer: "tr_00000000000000",
              source_refund: nil,
              currency: "usd",
              metadata: {
                payment_amount_reversed: 12_50,
                match_amount_reversed: 12_50,
                stripe_refund_id: "re_00000000000000",
                zuora_refund_id: "R-0000001",
                sponsors_listing_id: child_listing.id,
              },
            },
          ],
        },
      },
    )

    assert_difference(-> { fiscal_host_stripe.ledger_entries.count }, 3) do
      Billing::Stripe::Webhooks::TransferReversed.perform(webhook)
    end

    transfer_reversal_ledger_entry = fiscal_host_stripe.ledger_entries.transfer_reversal.last
    assert_equal "transfer_reversal", transfer_reversal_ledger_entry.transaction_type
    assert_equal(-25_00, transfer_reversal_ledger_entry.amount_in_subunits)
    assert_equal "USD", transfer_reversal_ledger_entry.currency_code
    assert_equal "trr_00000000000000", transfer_reversal_ledger_entry.primary_reference_id
    assert_equal child_listing, transfer_reversal_ledger_entry.sponsors_listing
    assert_equal "tr_00000000000000", transfer_reversal_ledger_entry.reversed_transfer_stripe_id
    assert_equal "re_00000000000000", transfer_reversal_ledger_entry.stripe_refund_id
    assert_equal "R-0000001", transfer_reversal_ledger_entry.zuora_refund_id
    assert_equal "ch_0000001", transfer_reversal_ledger_entry.refunded_transaction_stripe_id
    assert_equal "P-0000001", transfer_reversal_ledger_entry.refunded_transaction_zuora_id

    refund_ledger_entry = fiscal_host_stripe.ledger_entries.refund.last
    assert_equal "refund", refund_ledger_entry.transaction_type
    assert_equal 12_50, refund_ledger_entry.amount_in_subunits
    assert_equal "USD", refund_ledger_entry.currency_code
    assert_equal "R-0000001", refund_ledger_entry.primary_reference_id
    assert_equal child_listing, refund_ledger_entry.sponsors_listing
    assert_equal "re_00000000000000", refund_ledger_entry.stripe_refund_id
    assert_equal "ch_0000001", refund_ledger_entry.refunded_transaction_stripe_id
    assert_equal "paypal_id", refund_ledger_entry.refunded_transaction_paypal_id
    assert_equal "CBA-0123456",
      refund_ledger_entry.refunded_transaction_credit_balance_adjustment_number
    assert_equal "P-0000001", refund_ledger_entry.refunded_transaction_zuora_id

    github_match_reversal_ledger_entry = fiscal_host_stripe.ledger_entries.github_match_reversal.last
    assert_equal "github_match_reversal", github_match_reversal_ledger_entry.transaction_type
    assert_equal 12_50, github_match_reversal_ledger_entry.amount_in_subunits
    assert_equal "USD", github_match_reversal_ledger_entry.currency_code
    assert_equal "R-0000001", github_match_reversal_ledger_entry.primary_reference_id
    assert_equal child_listing, github_match_reversal_ledger_entry.sponsors_listing
    assert_nil github_match_reversal_ledger_entry.stripe_refund_id
    assert_nil github_match_reversal_ledger_entry.refunded_transaction_stripe_id
    assert_nil github_match_reversal_ledger_entry.refunded_transaction_paypal_id
    assert_nil github_match_reversal_ledger_entry
      .refunded_transaction_credit_balance_adjustment_number
    assert_nil github_match_reversal_ledger_entry.refunded_transaction_zuora_id
  end

  test "for a transfer with account deleted" do
    parent_listing = create(:sponsors_listing, :approved, :fiscal_host, :with_stripe_account)
    fiscal_host_stripe = parent_listing.active_stripe_connect_account
    child_listing = create(:sponsors_listing, :approved, :with_fiscal_host,
      parent_listing: parent_listing)

    # Mark fiscal_host_stripe as deleted
    fiscal_host_stripe.soft_delete

    webhook = create(
      :stripe_webhook,
      :transfer_reversed,
      object: {
        id: "tr_00000000000000",
        amount: 25_00,
        destination: fiscal_host_stripe.stripe_account_id,
        transfer_group: "P-0000001",
        metadata: {
          payment_amount: 12_50,
          match_amount: 12_50,
          stripe_charge_id: "ch_0000001",
          paypal_id: "paypal_id",
          credit_balance_adjustment_number: "CBA-0123456",
          sponsors_listing_id: child_listing.id,
        },
        reversals: {
          object: "list",
          data: [
            {
              id: "trr_00000000000000",
              amount: 25_00,
              transfer: "tr_00000000000000",
              source_refund: nil,
              currency: "usd",
              metadata: {
                payment_amount_reversed: 12_50,
                match_amount_reversed: 12_50,
                stripe_refund_id: "re_00000000000000",
                zuora_refund_id: "R-0000001",
                sponsors_listing_id: child_listing.id,
              },
            },
          ],
        },
      },
    )

    assert_difference(-> { fiscal_host_stripe.ledger_entries.count }, 3) do
      Billing::Stripe::Webhooks::TransferReversed.perform(webhook)
    end
  end

  test "for a transfer with several reversals" do
    stripe_connect_account = create(:stripe_connect_account)
    webhook = create(
      :stripe_webhook,
      :transfer_reversed,
      object: {
        id: "tr_00000000000000",
        amount: 25_00,
        destination: stripe_connect_account.stripe_account_id,
        transfer_group: "P-0000001",
        metadata: {
          payment_amount: 12_50,
          match_amount: 12_50,
          stripe_charge_id: "ch_0000001",
        },
        reversals: {
          object: "list",
          data: [
            {
              id: "trr_00000000000000",
              amount: 10_00,
              transfer: "tr_00000000000000",
              source_refund: nil,
              currency: "usd",
              metadata: {
                payment_amount_reversed: 5_00,
                match_amount_reversed: 5_00,
                stripe_refund_id: "re_00000000000000",
                zuora_refund_id: "R-0000001",
              },
            },
            {
              id: "trr_00000000000001",
              amount: 15_00,
              transfer: "tr_00000000000000",
              source_refund: nil,
              currency: "usd",
              metadata: {
                payment_amount_reversed: 7_50,
                match_amount_reversed: 7_50,
                stripe_refund_id: "re_00000000000001",
                zuora_refund_id: "R-0000002",
              },
            },
          ],
        },
      },
    )

    # Transfer Reversal trr_00000000000000 was already received
    create(
      :payouts_ledger_entry,
      :transfer_reversal,
      amount_in_subunits: -10_00,
      primary_reference_id: "trr_00000000000000",
      stripe_connect_account: stripe_connect_account,
    )
    create(
      :payouts_ledger_entry,
      :refund,
      amount_in_subunits: 5_00,
      primary_reference_id: "R-0000001",
      stripe_connect_account: stripe_connect_account,
    )
    create(
      :payouts_ledger_entry,
      :github_match_reversal,
      amount_in_subunits: 5_00,
      primary_reference_id: "R-0000001",
      stripe_connect_account: stripe_connect_account,
    )

    assert_difference(-> { stripe_connect_account.ledger_entries.count }, 3) do
      Billing::Stripe::Webhooks::TransferReversed.perform(webhook)
    end

    transfer_reversal_ledger_entry = stripe_connect_account.ledger_entries.transfer_reversal.last
    assert_equal "transfer_reversal", transfer_reversal_ledger_entry.transaction_type
    assert_equal(-15_00, transfer_reversal_ledger_entry.amount_in_subunits)
    assert_equal "USD", transfer_reversal_ledger_entry.currency_code
    assert_equal "trr_00000000000001", transfer_reversal_ledger_entry.primary_reference_id

    refund_ledger_entry = stripe_connect_account.ledger_entries.refund.last
    assert_equal "refund", refund_ledger_entry.transaction_type
    assert_equal 7_50, refund_ledger_entry.amount_in_subunits
    assert_equal "USD", refund_ledger_entry.currency_code
    assert_equal "R-0000002", refund_ledger_entry.primary_reference_id

    github_match_reversal_ledger_entry = stripe_connect_account.ledger_entries.github_match_reversal.last
    assert_equal "github_match_reversal", github_match_reversal_ledger_entry.transaction_type
    assert_equal 7_50, github_match_reversal_ledger_entry.amount_in_subunits
    assert_equal "USD", github_match_reversal_ledger_entry.currency_code
    assert_equal "R-0000002", github_match_reversal_ledger_entry.primary_reference_id
  end

  # See https://github.com/github/sponsors/issues/4554
  test "for a partial transfer reversal with missing reversal metadata and no match amount" do
    listing = create(:sponsors_listing, :approved, :with_stripe_account)
    stripe_account = listing.active_stripe_connect_account

    webhook = create(
      :stripe_webhook,
      :transfer_reversed,
      object: {
        id: "tr_00000000000000",
        amount: 25_00,
        amount_reversed: 15_00,
        destination: stripe_account.stripe_account_id,
        transfer_group: "P-0000001",
        metadata: {
          payment_amount: 25_00,
          match_amount: 0,
          stripe_charge_id: "ch_0000001",
          sponsors_listing_id: listing.id,
        },
        reversals: {
          object: "list",
          data: [
            {
              id: "trr_00000000000000",
              amount: 15_00,
              transfer: "tr_00000000000000",
              source_refund: nil,
              currency: "usd",
              metadata: {},
            },
          ],
        },
      },
    )

    assert_difference(-> { stripe_account.ledger_entries.count }, 2) do
      Billing::Stripe::Webhooks::TransferReversed.perform(webhook)
    end

    transfer_reversal_ledger_entry = stripe_account.ledger_entries.transfer_reversal.last
    assert_equal "transfer_reversal", transfer_reversal_ledger_entry.transaction_type
    assert_equal(-15_00, transfer_reversal_ledger_entry.amount_in_subunits)
    assert_equal "USD", transfer_reversal_ledger_entry.currency_code
    assert_equal "trr_00000000000000", transfer_reversal_ledger_entry.primary_reference_id
    assert_equal listing, transfer_reversal_ledger_entry.sponsors_listing
    assert_equal "tr_00000000000000", transfer_reversal_ledger_entry.reversed_transfer_stripe_id
    assert_equal "ch_0000001", transfer_reversal_ledger_entry.refunded_transaction_stripe_id

    refund_ledger_entry = stripe_account.ledger_entries.refund.last
    assert_equal "refund", refund_ledger_entry.transaction_type
    assert_equal 15_00, refund_ledger_entry.amount_in_subunits
    assert_equal "USD", refund_ledger_entry.currency_code
    assert_equal listing, refund_ledger_entry.sponsors_listing
    assert_equal "ch_0000001", refund_ledger_entry.refunded_transaction_stripe_id
  end

  test "creates a new transfer if transferring between connected accounts" do
    listing = create(:sponsors_listing, :approved, :with_stripe_account)
    inactive_stripe = create(:stripe_connect_account, :inactive, sponsors_listing: listing)
    stripe = listing.active_stripe_connect_account
    webhook = create(
      :stripe_webhook,
      :transfer_reversed,
      object: {
        id: "tr_00000000000000",
        amount: 25_00,
        destination: inactive_stripe.stripe_account_id,
        transfer_group: "P-0000001",
        metadata: {
          payment_amount: 12_50,
          match_amount: 12_50,
          stripe_charge_id: "ch_0000001",
          sponsors_listing_id: listing.id,
        },
        reversals: {
          object: "list",
          data: [
            {
              id: "trr_00000000000000",
              amount: 25_00,
              transfer: "tr_00000000000000",
              source_refund: nil,
              currency: "usd",
              metadata: {
                payment_amount_reversed: 12_50,
                match_amount_reversed: 12_50,
                sponsors_listing_id: listing.id,
                transfer_to: stripe.stripe_account_id,
              },
            },
          ],
        },
      },
    )

    Stripe::Transfer.expects(:create).once.with(
      amount: 25_00,
      currency: ::Billing::Stripe::TransferPayments::DEFAULT_CURRENCY,
      destination: stripe.stripe_account_id,
      transfer_group: "P-0000001",
      metadata: {
        payment_amount: 12_50,
        match_amount: 12_50,
        stripe_charge_id: "ch_0000001",
        sponsors_listing_id: listing.id,
        transferred_from_account: inactive_stripe.stripe_account_id,
        transferred_from_reversal: "trr_00000000000000"
      },
    )

    assert_difference(-> { inactive_stripe.ledger_entries.count }, 2) do
      Billing::Stripe::Webhooks::TransferReversed.perform(webhook)
    end

    transfer_reversal_ledger_entry = inactive_stripe.ledger_entries.transfer_reversal.last
    assert_equal "transfer_reversal", transfer_reversal_ledger_entry.transaction_type
    assert_equal(-25_00, transfer_reversal_ledger_entry.amount_in_subunits)
    assert_equal "USD", transfer_reversal_ledger_entry.currency_code
    assert_equal "trr_00000000000000", transfer_reversal_ledger_entry.primary_reference_id
    assert_equal listing, transfer_reversal_ledger_entry.sponsors_listing
    assert_equal "tr_00000000000000", transfer_reversal_ledger_entry.reversed_transfer_stripe_id
    assert_nil transfer_reversal_ledger_entry.stripe_refund_id
    assert_nil transfer_reversal_ledger_entry.zuora_refund_id
    assert_nil transfer_reversal_ledger_entry.refunded_transaction_stripe_id
    assert_nil transfer_reversal_ledger_entry.refunded_transaction_zuora_id

    inter_account_transfer_ledger_entry = inactive_stripe.ledger_entries.inter_account_transfer.last
    assert_equal "inter_account_transfer", inter_account_transfer_ledger_entry.transaction_type
    assert_equal 25_00, inter_account_transfer_ledger_entry.amount_in_subunits
    assert_equal "USD", inter_account_transfer_ledger_entry.currency_code
    assert_equal "trr_00000000000000:#{stripe.stripe_account_id}", inter_account_transfer_ledger_entry.primary_reference_id
    assert_equal listing, inter_account_transfer_ledger_entry.sponsors_listing
    assert_nil inter_account_transfer_ledger_entry.stripe_refund_id
    assert_nil inter_account_transfer_ledger_entry.refunded_transaction_stripe_id
    assert_nil inter_account_transfer_ledger_entry.refunded_transaction_paypal_id
    assert_nil inter_account_transfer_ledger_entry.refunded_transaction_credit_balance_adjustment_number
    assert_nil inter_account_transfer_ledger_entry.refunded_transaction_zuora_id
  end

  test "inter-account transfer fails when destination account belongs to another listing" do
    listing = create(:sponsors_listing, :approved, :with_stripe_account)
    other_listing_stripe = create(:stripe_connect_account, :inactive)

    refute_equal other_listing_stripe.sponsors_listing_id, listing.id

    stripe = listing.active_stripe_connect_account
    webhook = create(
      :stripe_webhook,
      :transfer_reversed,
      object: {
        id: "tr_00000000000000",
        amount: 25_00,
        destination: other_listing_stripe.stripe_account_id,
        transfer_group: "P-0000001",
        metadata: {
          payment_amount: 12_50,
          match_amount: 12_50,
          stripe_charge_id: "ch_0000001",
          sponsors_listing_id: listing.id,
        },
        reversals: {
          object: "list",
          data: [
            {
              id: "trr_00000000000000",
              amount: 25_00,
              transfer: "tr_00000000000000",
              source_refund: nil,
              currency: "usd",
              metadata: {
                payment_amount_reversed: 12_50,
                match_amount_reversed: 12_50,
                sponsors_listing_id: listing.id,
                transfer_to: stripe.stripe_account_id,
              },
            },
          ],
        },
      },
    )

    Stripe::Transfer.expects(:create).never

    assert_difference(-> { other_listing_stripe.ledger_entries.count }, 0) do
      assert_raises Billing::Stripe::Webhooks::TransferReversed::InvalidDestinationError do
        Billing::Stripe::Webhooks::TransferReversed.perform(webhook)
      end
    end

    refute_predicate webhook, :processed?
  end

  test "inter-account transfer fails for partial reversal" do
    listing = create(:sponsors_listing, :approved, :with_stripe_account)
    inactive_stripe = create(:stripe_connect_account, :inactive, sponsors_listing: listing)
    stripe = listing.active_stripe_connect_account

    webhook = create(
      :stripe_webhook,
      :transfer_reversed,
      object: {
        id: "tr_00000000000000",
        amount: 25_00,
        destination: inactive_stripe.stripe_account_id,
        transfer_group: "P-0000001",
        metadata: {
          payment_amount: 12_50,
          match_amount: 12_50,
          stripe_charge_id: "ch_0000001",
          sponsors_listing_id: listing.id,
        },
        reversals: {
          object: "list",
          data: [
            {
              id: "trr_00000000000001",
              amount: 15_00,
              transfer: "tr_00000000000000",
              source_refund: nil,
              currency: "usd",
              metadata: {
                payment_amount_reversed: 7_50,
                match_amount_reversed: 7_50,
                sponsors_listing_id: listing.id,
                transfer_to: stripe.stripe_account_id,
              },
            },
          ],
        },
      },
    )

    Stripe::Transfer.expects(:create).never

    assert_difference(-> { inactive_stripe.ledger_entries.count }, 0) do
      assert_raises Billing::Stripe::Webhooks::TransferReversed::InvalidTransferError do
        Billing::Stripe::Webhooks::TransferReversed.perform(webhook)
      end
    end

    refute_predicate webhook, :processed?
  end

  test "instruments a transfer reversal event for sponsors transfer reversals" do
    sponsoring_user = create(:credit_card_user,
      plan_subscription: create(:billing_plan_subscription), plan: GitHub::Plan.free_with_addons)
    sponsorable = create(:user)
    sponsors_listing = create(:sponsors_listing, :approved, sponsorable: sponsorable)
    tier = create(:sponsors_tier, :published, sponsors_listing: sponsors_listing)
    sponsorship = create(:sponsorship, sponsor: sponsoring_user, sponsorable: sponsorable,
      tier: tier)
    stripe_connect_account = create(:stripe_connect_account, sponsors_listing: sponsors_listing)
    create(:billing_transaction, user: sponsoring_user, transaction_id: "re_00000000000000")

    webhook = create(
      :stripe_webhook,
      :transfer_reversed,
      object: {
        id: "tr_00000000000000",
        amount: 25_00,
        destination: stripe_connect_account.stripe_account_id,
        transfer_group: "P-0000001",
        metadata: {
          payment_amount: 12_50,
          match_amount: 12_50,
          stripe_charge_id: "ch_0000001",
        },
        reversals: {
          object: "list",
          data: [
            {
              id: "trr_00000000000000",
              amount: 10_00,
              transfer: "tr_00000000000000",
              source_refund: nil,
              currency: "usd",
              metadata: {
                payment_amount_reversed: 5_00,
                match_amount_reversed: 5_00,
                stripe_refund_id: "re_00000000000000",
                zuora_refund_id: "R-0000001",
              },
            },
          ],
        },
      },
    )

    Billing::Stripe::Webhooks::TransferReversed.perform(webhook)

    assert_hydro_published({
      sponsorship: Hydro::EntitySerializer.sponsorship(sponsorship),
      listing: Hydro::EntitySerializer.sponsors_listing(sponsors_listing),
      tier: Hydro::EntitySerializer.sponsors_tier(tier),
      currency_code: "USD",
      total_amount_in_subunits: 10_00,
      payment_amount_in_subunits: 5_00,
      match_amount_in_subunits: 5_00,
      listing_stafftools_metadata: Hydro::EntitySerializer.sponsors_listing_stafftools_metadata(
        sponsors_listing.stafftools_metadata,
      ),
    }, schema: "github.sponsors.v1.SponsorshipTransferReversal")
  end

  test "clears match_limit_reached_at on listing in metadata if limit is no longer met after reversal" do
    sponsoring_user = create(:credit_card_user,
      plan_subscription: create(:billing_plan_subscription), plan: GitHub::Plan.free_with_addons)
    sponsorable = create(:user)
    sponsors_listing = create(:sponsors_listing, :approved,
      sponsorable: sponsorable, match_limit_reached_at: 3.days.ago)
    tier = create(:sponsors_tier, :published, sponsors_listing: sponsors_listing)
    sponsorship = create(:sponsorship, sponsor: sponsoring_user, sponsorable: sponsorable)
    stripe_connect_account = create(:stripe_connect_account, sponsors_listing: sponsors_listing)
    create(:billing_transaction, user: sponsoring_user, transaction_id: "re_00000000000000")

    refute_nil sponsors_listing.match_limit_reached_at
    SponsorsListing.any_instance.stubs(:reached_match_limit?).returns(false)

    webhook = create(
      :stripe_webhook,
      :transfer_reversed,
      object: {
        id: "tr_00000000000000",
        amount: 25_00,
        destination: stripe_connect_account.stripe_account_id,
        transfer_group: "P-0000001",
        metadata: {
          payment_amount: 12_50,
          match_amount: 12_50,
          stripe_charge_id: "ch_0000001",
          sponsors_listing_id: sponsors_listing.id,
        },
        reversals: {
          object: "list",
          data: [
            {
              id: "trr_00000000000000",
              amount: 10_00,
              transfer: "tr_00000000000000",
              source_refund: nil,
              currency: "usd",
              metadata: {
                payment_amount_reversed: 5_00,
                match_amount_reversed: 5_00,
                stripe_refund_id: "re_00000000000000",
                zuora_refund_id: "R-0000001",
              },
            },
          ],
        },
      },
    )

    Billing::Stripe::Webhooks::TransferReversed.perform(webhook)
    assert_nil sponsors_listing.reload.match_limit_reached_at
  end

  test "clears match_limit_reached_at on listing for Stripe account if limit is no longer met after reversal and no listing ID in metadata" do
    sponsoring_user = create(:credit_card_user,
      plan_subscription: create(:billing_plan_subscription), plan: GitHub::Plan.free_with_addons)
    sponsorable = create(:user)
    sponsors_listing = create(:sponsors_listing, :approved,
      sponsorable: sponsorable, match_limit_reached_at: 3.days.ago)
    tier = create(:sponsors_tier, :published, sponsors_listing: sponsors_listing)
    sponsorship = create(:sponsorship, sponsor: sponsoring_user, sponsorable: sponsorable)
    stripe_connect_account = create(:stripe_connect_account, sponsors_listing: sponsors_listing)
    create(:billing_transaction, user: sponsoring_user, transaction_id: "re_00000000000000")

    refute_nil stripe_connect_account.sponsors_listing.match_limit_reached_at
    SponsorsListing.any_instance.stubs(:reached_match_limit?).returns(false)

    webhook = create(
      :stripe_webhook,
      :transfer_reversed,
      object: {
        id: "tr_00000000000000",
        amount: 25_00,
        destination: stripe_connect_account.stripe_account_id,
        transfer_group: "P-0000001",
        metadata: {
          payment_amount: 12_50,
          match_amount: 12_50,
          stripe_charge_id: "ch_0000001",
        },
        reversals: {
          object: "list",
          data: [
            {
              id: "trr_00000000000000",
              amount: 10_00,
              transfer: "tr_00000000000000",
              source_refund: nil,
              currency: "usd",
              metadata: {
                payment_amount_reversed: 5_00,
                match_amount_reversed: 5_00,
                stripe_refund_id: "re_00000000000000",
                zuora_refund_id: "R-0000001",
              },
            },
          ],
        },
      },
    )

    Billing::Stripe::Webhooks::TransferReversed.perform(webhook)
    assert_nil stripe_connect_account.sponsors_listing.reload.match_limit_reached_at
  end

  test "does not clear match_limit_reached_at if limit is still met after reversal" do
    sponsoring_user = create(:credit_card_user,
      plan_subscription: create(:billing_plan_subscription), plan: GitHub::Plan.free_with_addons)
    sponsorable = create(:user)
    sponsors_listing = create(:sponsors_listing, :approved, sponsorable: sponsorable,
      match_limit_reached_at: 3.days.ago)
    tier = create(:sponsors_tier, :published, sponsors_listing: sponsors_listing)
    sponsorship = create(:sponsorship, sponsor: sponsoring_user, sponsorable: sponsorable)
    stripe_connect_account = create(:stripe_connect_account, sponsors_listing: sponsors_listing)
    create(:billing_transaction, user: sponsoring_user, transaction_id: "re_00000000000000")

    refute_nil sponsors_listing.match_limit_reached_at
    SponsorsListing.any_instance.stubs(:reached_match_limit?).returns(true)

    webhook = create(
      :stripe_webhook,
      :transfer_reversed,
      object: {
        id: "tr_00000000000000",
        amount: 25_00,
        destination: stripe_connect_account.stripe_account_id,
        transfer_group: "P-0000001",
        metadata: {
          payment_amount: 12_50,
          match_amount: 12_50,
          stripe_charge_id: "ch_0000001",
        },
        reversals: {
          object: "list",
          data: [
            {
              id: "trr_00000000000000",
              amount: 10_00,
              transfer: "tr_00000000000000",
              source_refund: nil,
              currency: "usd",
              metadata: {
                payment_amount_reversed: 5_00,
                match_amount_reversed: 5_00,
                stripe_refund_id: "re_00000000000000",
                zuora_refund_id: "R-0000001",
              },
            },
          ],
        },
      },
    )

    Billing::Stripe::Webhooks::TransferReversed.perform(webhook)
    refute_nil sponsors_listing.reload.match_limit_reached_at
  end

  test "handles match reversals without a refund by using the reversal_id and not creating a refund entry" do
    reversal_id = "trr_00000000000000"
    billing_transaction = create(:billing_transaction, platform_transaction_id: reversal_id)
    stripe_connect_account = create(:stripe_connect_account)
    webhook = create(
      :stripe_webhook,
      :transfer_reversed,
      object: {
        id: "tr_00000000000000",
        amount: 10_00,
        amount_reversed: 3_25,
        destination: stripe_connect_account.stripe_account_id,
        transfer_group: "P-0000001",
        metadata: {
          payment_amount: 5_00,
          match_amount: 5_00,
          stripe_charge_id: "ch_0000001",
        },
        reversals: {
          object: "list",
          data: [
            {
              id: reversal_id,
              amount: 3_25,
              transfer: "tr_00000000000000",
              currency: "usd",
              metadata: {
                payment_amount_reversed: 0,
                match_amount_reversed: 3_25,
              },
            },
          ],
        },
      },
    )

    # There are only two ledger entries because we are do not create a zero dollar refund entry
    assert_difference(-> { stripe_connect_account.ledger_entries.count }, 2) do
      Billing::Stripe::Webhooks::TransferReversed.perform(webhook)
    end

    transfer_reversal_ledger_entry = stripe_connect_account.ledger_entries.transfer_reversal.last
    assert_equal "transfer_reversal", transfer_reversal_ledger_entry.transaction_type
    assert_equal(-3_25, transfer_reversal_ledger_entry.amount_in_subunits)
    assert_equal "USD", transfer_reversal_ledger_entry.currency_code
    assert_equal "trr_00000000000000", transfer_reversal_ledger_entry.primary_reference_id
    assert_equal "tr_00000000000000", transfer_reversal_ledger_entry.reversed_transfer_stripe_id
    assert_equal billing_transaction, transfer_reversal_ledger_entry.billing_transaction
    assert_nil transfer_reversal_ledger_entry.stripe_refund_id
    assert_nil transfer_reversal_ledger_entry.zuora_refund_id

    reversal_ledger_entry = stripe_connect_account.ledger_entries.github_match_reversal.last

    assert_equal "github_match_reversal", reversal_ledger_entry.transaction_type
    assert_equal 3_25, reversal_ledger_entry.amount_in_subunits
    assert_equal "USD", reversal_ledger_entry.currency_code
    assert_equal billing_transaction, reversal_ledger_entry.billing_transaction
    # There is no refund for a pure match reversal, so lets use the reversal_id as the primary
    assert_equal "trr_00000000000000", reversal_ledger_entry.primary_reference_id
    assert_nil reversal_ledger_entry.reversed_transfer_stripe_id
    assert_nil reversal_ledger_entry.stripe_refund_id
    assert_nil reversal_ledger_entry.zuora_refund_id
  end

  test "for an invoiced sponsorship transfer" do
    stripe_connect_account = create(:stripe_connect_account)
    zuora_purchase_id = "2c92a00d6ff0e96f0170168b81415536"
    invoiced_sponsorship_transfer_reversal_id = 2
    webhook = create(
      :stripe_webhook,
      :transfer_reversed,
      object: {
        id: "tr_00000000000000",
        amount: 100_00,
        destination: stripe_connect_account.stripe_account_id,
        transfer_group: zuora_purchase_id,
        metadata: {
          payment_amount: 100_00,
          match_amount: 0,
          invoiced_sponsorship_transfer_id: 1,
          sponsor_id: 1,
          actor_id: 1,
        },
        reversals: {
          object: "list",
          data: [
            {
              id: "trr_00000000000000",
              amount: 100_00,
              transfer: "tr_00000000000000",
              source_refund: nil,
              currency: "usd",
              metadata: {
                payment_amount_reversed: 100_00,
                match_amount_reversed: 0,
                invoiced_sponsorship_transfer_reversal_id: invoiced_sponsorship_transfer_reversal_id,
                actor_id: 3,
              },
            },
          ],
        },
      },
    )

    assert_difference(-> { stripe_connect_account.ledger_entries.count }, 2) do
      Billing::Stripe::Webhooks::TransferReversed.perform(webhook)
    end

    transfer_reversal_ledger_entry = stripe_connect_account.ledger_entries.transfer_reversal.last
    assert_equal "transfer_reversal", transfer_reversal_ledger_entry.transaction_type
    assert_equal(-100_00, transfer_reversal_ledger_entry.amount_in_subunits)
    assert_equal "USD", transfer_reversal_ledger_entry.currency_code
    assert_equal "trr_00000000000000", transfer_reversal_ledger_entry.primary_reference_id
    assert_equal "tr_00000000000000", transfer_reversal_ledger_entry.reversed_transfer_stripe_id
    assert_equal zuora_purchase_id, transfer_reversal_ledger_entry.refunded_transaction_zuora_id
    assert_equal invoiced_sponsorship_transfer_reversal_id,
      transfer_reversal_ledger_entry.invoiced_sponsorship_transfer_reversal_id

    invoice_credit_ledger_entry = stripe_connect_account.ledger_entries.invoice_credit.last
    assert_equal "invoice_credit", invoice_credit_ledger_entry.transaction_type
    assert_equal 100_00, invoice_credit_ledger_entry.amount_in_subunits
    assert_equal "USD", invoice_credit_ledger_entry.currency_code
    assert_equal invoiced_sponsorship_transfer_reversal_id.to_s,
      invoice_credit_ledger_entry.primary_reference_id
    assert_equal zuora_purchase_id, invoice_credit_ledger_entry.refunded_transaction_zuora_id

    # We don't generate Sponsorship records for invoiced sponsorships yet,
    # so don't worry about firing this Hydro event for now.
    refute_hydro_messages(schema: "github.sponsors.v1.SponsorshipTransferReversal")
  end
end
