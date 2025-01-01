# typed: true
# frozen_string_literal: true

require "test_helper"

class SponsorsListingStripeDependencyTest < GitHub::TestCase
  include GitHub::Billing::CurrencyTestHelper
  include HydroTestHelpers
  include SponsorsListingTestHelper

  fixtures do
    @listing_without_stripe = create(:sponsors_listing, :approved, :exempt_from_payout_probation)

    @listing_with_stripe = create(:sponsors_listing, :with_stripe_account)
    @stripe_account = @listing_with_stripe.active_stripe_connect_account

    @org_listing = create(:sponsors_listing, :for_org, :approved)

    @fiscal_host_listing = create(:sponsors_listing, :fiscal_host, :with_stripe_account)
    @fiscal_host_stripe = @fiscal_host_listing.active_stripe_connect_account
    @child_listing = create(:sponsors_listing, :approved, :with_fiscal_host,
      parent_listing: @fiscal_host_listing)
  end

  setup do
    skip unless GitHub.sponsors_enabled?
    setup_currency_exchange
  end

  def stub_stripe_balance(amount:)
    fake_balance_result = stub(available: [stub(amount: amount)])
    fake_balance_object = stub(success?: true, result: fake_balance_result)
    Billing::StripeConnect::Account.any_instance.stubs(:current_balance).
      returns(fake_balance_object)
  end

  context "#stripe_country_flag_emoji_alias" do
    test "returns emoji alias for the listing's active Stripe account's country's flag" do
      @listing_with_stripe.update_attribute(:country_of_residence, nil)

      EXPECTED_EMOJI_ALIASES_BY_COUNTRY_CODE.each do |country_code, expected_alias|
        @stripe_account.update!(country: country_code)
        @listing_with_stripe.reload_active_stripe_connect_account
        @listing_with_stripe.reset_memoized_attributes # clear memoization from previous loop
        assert_equal country_code, @listing_with_stripe.stripe_country

        result = @listing_with_stripe.stripe_country_flag_emoji_alias

        assert_equal expected_alias, result
        refute_nil Emoji.find_by_alias(result), "returned string should be an emoji alias"
      end
    end

    test "returns nil when listing has no active Stripe account" do
      assert_nil @listing_without_stripe.stripe_country_flag_emoji_alias
    end
  end

  context "#waiting_to_see_if_stripe_tax_verification_is_required?" do
    test "returns 'true' if there is no Stripe Connect Account" do
      assert_predicate @listing_without_stripe, :waiting_to_see_if_stripe_tax_verification_is_required?
    end

    test "returns 'true' if the Stripe Connect Account is not synced" do
      listing = create(:sponsors_listing)
      create(:stripe_connect_account, :not_synced, sponsors_listing: listing)
      assert_predicate listing, :waiting_to_see_if_stripe_tax_verification_is_required?
    end

    test "returns 'false' if the Stripe Connect Account is synced" do
      refute_predicate @listing_with_stripe, :waiting_to_see_if_stripe_tax_verification_is_required?
    end
  end

  context "#stripe_payouts_sorted_by_created" do
    test "returns empty Array when account has no payouts" do
      @stripe_account.update!(stripe_account_id: "acct_1J4sf32RWJvg9wlo")

      payouts_sorted_by_created = VCR.use_cassette("stripe/list_paid_payouts_no_results") do
        @listing_with_stripe.stripe_payouts_sorted_by_created
      end

      assert_empty payouts_sorted_by_created
    end

    test "includes payouts from all Stripe accounts owned by the listing" do
      @stripe_account.update!(stripe_account_id: "acct_1IF4dJ2Q42qEzmMv")
      stripe_account2 = create(:stripe_connect_account, :inactive, sponsors_listing: @listing_with_stripe,
        stripe_account_id: "acct_1JCwpS2SjumVcZJ1")

      stripe_payouts_sorted_by_created = VCR.use_cassette("stripe/list_paid_payouts_from_multiple_accounts") do
        @listing_with_stripe.stripe_payouts_sorted_by_created
      end
      assert_equal 3, stripe_payouts_sorted_by_created.size

      payout_with_stripe_account_id1 = stripe_payouts_sorted_by_created.first
      payout_with_stripe_account_id2 = stripe_payouts_sorted_by_created.second
      payout_with_stripe_account_id3 = stripe_payouts_sorted_by_created.third
      payout1 = payout_with_stripe_account_id1.stripe_payout
      payout2 = payout_with_stripe_account_id2.stripe_payout
      payout3 = payout_with_stripe_account_id3.stripe_payout

      assert_operator payout1.created, :>, payout2.created
      assert_operator payout2.created, :>, payout3.created

      assert_equal "acct_1IF4dJ2Q42qEzmMv", payout_with_stripe_account_id1.stripe_account_id
      assert_equal "acct_1JCwpS2SjumVcZJ1", payout_with_stripe_account_id2.stripe_account_id
      assert_equal "acct_1IF4dJ2Q42qEzmMv", payout_with_stripe_account_id3.stripe_account_id
    end
  end

  context "#total_paid_out_by_year" do
    test "does not include Stripe account that has no payouts" do
      @stripe_account.update!(stripe_account_id: "acct_1J4sf32RWJvg9wlo")

      total_paid_out_by_year = VCR.use_cassette("stripe/list_paid_payouts_no_results") do
        @listing_with_stripe.total_paid_out_by_year
      end

      assert_empty total_paid_out_by_year
    end

    test "includes total payout sums grouped by year" do
      @stripe_account.update!(stripe_account_id: "acct_1Ep35IFxJZYbadPl")

      total_paid_out_by_year = VCR.use_cassette("stripe/list_payouts_by_year") do
        @listing_with_stripe.total_paid_out_by_year
      end

      assert_equal 3, total_paid_out_by_year.size

      total_2021 = total_paid_out_by_year[2021]
      assert_instance_of Billing::Money, total_2021
      assert_equal Billing::Money.new(26330), total_2021

      total_2020 = total_paid_out_by_year[2020]
      assert_instance_of Billing::Money, total_2020
      assert_equal Billing::Money.new(16295), total_2020

      total_2019 = total_paid_out_by_year[2019]
      assert_instance_of Billing::Money, total_2019
      assert_equal Billing::Money.new(1500), total_2019
    end

    test "includes total payout sums grouped by year with limit" do
      @stripe_account.update!(stripe_account_id: "acct_1Ep35IFxJZYbadPl")

      total_paid_out_by_year = VCR.use_cassette("stripe/list_payouts_by_year_with_limit") do
        @listing_with_stripe.total_paid_out_by_year(limit: 2)
      end

      assert_equal 1, total_paid_out_by_year.size

      total_2021 = total_paid_out_by_year[2021]
      assert_instance_of Billing::Money, total_2021
      assert_equal Billing::Money.new(6100), total_2021
    end
  end

  context "ledger_entries relation" do
    test "includes ledger entry for listing's active Stripe account" do
      ledger_entry = create(:payouts_ledger_entry, :transfer,
        stripe_connect_account: @stripe_account, sponsors_listing: @listing_with_stripe)
      assert_equal [ledger_entry], @listing_with_stripe.ledger_entries
    end

    test "includes ledger entry for listing's inactive Stripe account" do
      inactive_stripe = create(:stripe_connect_account, :inactive, sponsors_listing: @listing_with_stripe)
      ledger_entry = create(:payouts_ledger_entry, :transfer,
        stripe_connect_account: inactive_stripe, sponsors_listing: @listing_with_stripe)
      assert_includes @listing_with_stripe.ledger_entries, ledger_entry
    end

    test "includes ledger entry for fiscally hosted listing from fiscal host's inactive Stripe account" do
      inactive_parent_stripe = create(:stripe_connect_account, :inactive,
        sponsors_listing: @fiscal_host_listing)
      ledger_entry = create(:payouts_ledger_entry, :transfer,
        stripe_connect_account: inactive_parent_stripe, sponsors_listing: @child_listing)
      assert_includes @child_listing.ledger_entries, ledger_entry
    end

    test "includes ledger entry for fiscally hosted listing from its fiscal host's active Stripe account" do
      ledger_entry = create(:payouts_ledger_entry, :transfer,
        stripe_connect_account: @fiscal_host_stripe, sponsors_listing: @child_listing)

      assert_equal [ledger_entry], @child_listing.ledger_entries
    end

    # https://github.com/github/sponsors/issues/2601
    test "includes ledger entries for fiscally hosted listing from its fiscal host's Stripe and personal Stripe" do
      inactive_child_stripe = create(:stripe_connect_account, :inactive, sponsors_listing: @child_listing)
      ledger_entry1 = create(:payouts_ledger_entry, :transfer,
        stripe_connect_account: @fiscal_host_stripe, sponsors_listing: @child_listing)
      ledger_entry2 = create(:payouts_ledger_entry, :transfer,
        stripe_connect_account: inactive_child_stripe, sponsors_listing: @child_listing)

      assert_same_elements [ledger_entry1, ledger_entry2], @child_listing.ledger_entries
    end
  end

  context "#stripe_connect_account_ids_for_self_or_fiscal_host" do
    test "returns just listing's personal Stripe ID when it has no fiscal host" do
      assert_equal Set.new([@stripe_account.id]),
        @listing_with_stripe.stripe_connect_account_ids_for_self_or_fiscal_host
    end

    test "returns listing + fiscal host's Stripe IDs" do
      child_stripe = create(:stripe_connect_account, sponsors_listing: @child_listing)
      assert_same_elements [@fiscal_host_stripe.id, child_stripe.id],
        @child_listing.stripe_connect_account_ids_for_self_or_fiscal_host
    end

    test "returns fiscal host's Stripe ID when listing has no Stripe of its own" do
      assert_equal Set.new([@fiscal_host_stripe.id]),
        @child_listing.stripe_connect_account_ids_for_self_or_fiscal_host
    end

    test "returns an empty list when listing has no Stripe and no parent" do
      assert_empty @listing_without_stripe.stripe_connect_account_ids_for_self_or_fiscal_host
    end

    test "returns an empty list when listing and its parent have no Stripe" do
      @fiscal_host_stripe.delete
      assert_empty @child_listing.stripe_connect_account_ids_for_self_or_fiscal_host
    end

    test "returns an empty list for an unsaved listing" do
      assert_empty build(:sponsors_listing).stripe_connect_account_ids_for_self_or_fiscal_host
    end

    test "includes inactive Stripe account ID for listing" do
      inactive_stripe = create(:stripe_connect_account, :inactive, sponsors_listing: @listing_with_stripe)
      result = @listing_with_stripe.stripe_connect_account_ids_for_self_or_fiscal_host
      assert_includes result, inactive_stripe.id
    end
  end

  context "#within_stripe_account_limit?" do
    test "true when listing has no Stripe accounts" do
      assert_predicate @listing_without_stripe, :within_stripe_account_limit?
    end

    test "true when listing has fewer Stripe accounts than the limit" do
      assert_predicate @listing_with_stripe, :within_stripe_account_limit?
    end

    test "false when listing has as many Stripe accounts as we allow" do
      Billing::StripeConnect::Account.stub_const(:MAX_ACCOUNTS_PER_SPONSORS_LISTING, 1) do
        refute_predicate @listing_with_stripe, :within_stripe_account_limit?
      end
    end
  end

  context "#active_stripe_account_for_self_or_fiscal_host" do
    test "returns Stripe account for fiscal host parent" do
      assert_equal @fiscal_host_stripe,
        @child_listing.active_stripe_account_for_self_or_fiscal_host
    end

    test "returns Stripe account for listing" do
      assert_equal @stripe_account,
        @listing_with_stripe.active_stripe_account_for_self_or_fiscal_host
    end

    test "returns the fiscal host's Stripe account when listing has both a fiscal host and an active stripe account" do
      create(:stripe_connect_account, sponsors_listing: @child_listing)

      refute_nil @child_listing.active_stripe_connect_account

      assert_equal @fiscal_host_stripe, @child_listing.stripe_transfer_account
    end

    test "returns nil when listing has no parent and no Stripe account" do
      assert_nil @listing_without_stripe.parent_listing, "need a listing with no parent"
      assert_nil @listing_without_stripe.active_stripe_account_for_self_or_fiscal_host
    end

    test "returns nil when fiscal host has no Stripe account and neither does the listing itself" do
      @fiscal_host_stripe.destroy!
      assert_nil @child_listing.active_stripe_account_for_self_or_fiscal_host
    end

    test "returns nil when fiscal host has only an inactive Stripe account and listing has no Stripe account" do
      @fiscal_host_stripe.update!(active: false)
      assert_nil @child_listing.active_stripe_account_for_self_or_fiscal_host
    end

    test "returns nil when listing has only an inactive Stripe account" do
      @stripe_account.update!(active: false)
      assert_nil @listing_with_stripe.active_stripe_account_for_self_or_fiscal_host
    end

    test "returns nil when listing and fiscal host only have inactive Stripe accounts" do
      @fiscal_host_stripe.update!(active: false)
      create(:stripe_connect_account, :inactive, sponsors_listing: @child_listing)
      assert_nil @child_listing.active_stripe_account_for_self_or_fiscal_host
    end
  end

  context "active_parent_stripe_connect_account relation" do
    test "returns Stripe account for fiscal host parent" do
      assert_equal @fiscal_host_stripe, @child_listing.active_parent_stripe_connect_account
    end

    test "returns nil when listing has no parent" do
      assert_nil @listing_with_stripe.parent_listing, "need a listing with no parent"
      assert_nil @listing_with_stripe.active_parent_stripe_connect_account
    end

    test "returns nil when fiscal host has no Stripe account" do
      @fiscal_host_stripe.destroy!
      assert_nil @child_listing.active_parent_stripe_connect_account
    end

    test "returns nil when fiscal host has only an inactive Stripe account" do
      @fiscal_host_stripe.update!(active: false)
      assert_nil @child_listing.active_parent_stripe_connect_account
    end
  end

  context "#stripe_verified?" do
    test "false when listing does not have a Stripe account" do
      refute_predicate @listing_without_stripe, :stripe_verified?
    end

    test "true when Stripe is verified" do
      assert_predicate @stripe_account, :verified_verification_status?,
        "need a Stripe account that's verified"
      assert_predicate @listing_with_stripe, :stripe_verified?
    end

    test "false when Stripe is not verified" do
      account = create(:stripe_connect_account, :unverified, sponsors_listing: @listing_without_stripe)
      refute_predicate @listing_without_stripe, :stripe_verified?
    end

    test "true when listing has a fiscal host with a verified Stripe account" do
      assert_predicate @child_listing, :stripe_verified?
    end

    test "false when listing has a fiscal host without w8 or w9" do
      child_listing = create(:sponsors_listing, :approved, :with_fiscal_host)

      refute_predicate child_listing.parent_listing, :stripe_verified?
      refute_predicate child_listing.parent_listing, :stripe_w8_or_w9_verified?

      refute_predicate child_listing, :stripe_w8_or_w9_verified?
      refute_predicate child_listing, :stripe_verified?
    end
  end

  context "#eligible_for_stripe_connect?" do
    test "true if billing country is supported" do
      @listing_with_stripe.update!(billing_country: "US")
      assert_predicate @listing_with_stripe, :eligible_for_stripe_connect?
    end

    test "false if billing country is not supported" do
      unsupported_country = Billing::StripeConnect::Account.unsupported_countries.first
      @stripe_account.update!(billing_country: unsupported_country)
      @listing_with_stripe.update!(billing_country: unsupported_country)

      refute_predicate @listing_with_stripe, :eligible_for_stripe_connect?
    end
  end

  context "payouts_enabled scope" do
    test "includes listings with Stripe accounts that have payouts enabled" do
      payouts_enabled_account = create(:stripe_connect_account, payouts_enabled: true)
      assert_predicate payouts_enabled_account, :payouts_enabled?
      payouts_disabled_account = create(:stripe_connect_account, :payouts_disabled)
      no_stripe_listing = create(:sponsors_listing)
      all_listings = [payouts_enabled_account.sponsors_listing_id,
        payouts_disabled_account.sponsors_listing_id, no_stripe_listing.id]

      result = SponsorsListing.where(id: all_listings).payouts_enabled

      assert_includes result, payouts_enabled_account.sponsors_listing
      refute_includes result, payouts_disabled_account.sponsors_listing
      refute_includes result, no_stripe_listing
    end
  end

  context "#stripe_tax_forms_completed?" do
    test "false when listing does not have a Stripe account" do
      refute_predicate @listing_without_stripe, :stripe_tax_forms_completed?
    end

    test "false when 1099-MISC has not been requested for the Stripe account" do
      listing = create(:sponsors_listing, :approved)
      stripe_account = create(:stripe_connect_account, sponsors_listing: listing,
        stripe_account_id: "acct_1Gdg4SGfzt2kDZmO")

      VCR.use_cassette("stripe/retrieve_capability") do
        refute_predicate listing, :stripe_tax_forms_completed?
      end
    end

    test "false when Stripe API request fails for 1099-MISC check" do
      listing = create(:sponsors_listing, :approved)
      stripe_account = create(:stripe_connect_account, sponsors_listing: listing,
        stripe_account_id: "acct_1Gi4HFEmaMEzWuJu") # Canadian account

      VCR.use_cassette("stripe/failed_retrieve_capability") do
        refute_predicate listing, :stripe_tax_forms_completed?
      end
    end

    test "false when not all of Stripe's requirements for a 1099-MISC have been met" do
      listing = create(:sponsors_listing, :approved)
      stripe_account = create(:stripe_connect_account, sponsors_listing: listing,
        stripe_account_id: "acct_1GuPRRIUvEAaxtx6")

      VCR.use_cassette("stripe/retrieve_requested_capability") do
        refute_predicate listing, :stripe_tax_forms_completed?
      end
    end

    test "true when Stripe's requirements have been met" do
      listing = create(:sponsors_listing, :approved)
      stripe_account = create(:stripe_connect_account, sponsors_listing: listing,
        stripe_account_id: "acct_1Ep35IFxJZYbadPl")

      VCR.use_cassette("stripe/retrieve_fulfilled_capability") do
        assert_predicate listing, :stripe_tax_forms_completed?
      end
    end
  end

  context "#eligible_for_stripe_taxes?" do
    test "returns true if sponsorable resides in the US" do
      @listing_without_stripe.update!(country_of_residence: "US")

      assert_predicate @listing_without_stripe.active_stripe_connect_account, :blank?
      assert_predicate @listing_without_stripe, :eligible_for_stripe_taxes?
    end

    test "returns false if sponsorable resides outside the US" do
      @listing_without_stripe.update!(country_of_residence: "ES")

      assert_predicate @listing_without_stripe.active_stripe_connect_account, :blank?
      refute_predicate @listing_without_stripe, :eligible_for_stripe_taxes?
    end

    test "returns true for sponsorable with Stripe account in the US ignoring country_of_residence" do
      @listing_with_stripe.active_stripe_connect_account.update!(country: "US")
      @listing_with_stripe.update_attribute(:country_of_residence, "SV")

      assert_predicate @listing_with_stripe.active_stripe_connect_account, :present?
      assert_predicate @listing_with_stripe, :eligible_for_stripe_taxes?
    end

    test "returns false for sponsorable with Stripe account outside the US ignoring country_of_residence" do
      @listing_with_stripe.active_stripe_connect_account.update!(country: "SV")
      @listing_with_stripe.update_attribute(:country_of_residence, "US")

      assert_predicate @listing_with_stripe.active_stripe_connect_account, :present?
      refute_predicate @listing_with_stripe, :eligible_for_stripe_taxes?
    end

    test "returns false if listing uses a fiscal host" do
      child_listing = create(:sponsors_listing, :approved, :for_org, :with_fiscal_host,
        country_of_residence: "US")
      refute_predicate child_listing, :eligible_for_stripe_taxes?
    end
  end

  context "#stripe_transfer_account" do
    test "returns nil when listing has no Stripe account" do
      assert_nil @listing_without_stripe.stripe_transfer_account
    end

    test "returns nil when listing has only an inactive Stripe account" do
      create(:stripe_connect_account, :inactive, sponsors_listing: @listing_without_stripe)
      assert_nil @listing_without_stripe.stripe_transfer_account
    end

    test "returns listing's active Stripe account" do
      assert_equal @stripe_account, @listing_with_stripe.stripe_transfer_account
    end

    test "returns fiscal host's Stripe when listing uses a fiscal host with Stripe" do
      assert_equal @fiscal_host_stripe, @child_listing.stripe_transfer_account
    end
  end

  context "#stripe_transfers_enabled?" do
    test "returns false if Stripe account doesn't exist and listing doesn't use a fiscal host" do
      refute_predicate @listing_without_stripe, :stripe_transfers_enabled?
    end

    test "returns true if Stripe account exists" do
      assert_predicate @listing_with_stripe, :stripe_transfers_enabled?
    end

    test "returns true if listing uses a fiscal host with a Stripe account" do
      assert_predicate @child_listing, :stripe_transfers_enabled?
    end
  end

  context "#total_match_in_cents" do
    test "includes match reversals" do
      create_list(:payouts_ledger_entry, 2, :github_match,
        stripe_connect_account: @stripe_account,
        sponsors_listing: @listing_with_stripe,
        amount_in_subunits: -20_00
      )
      create(:payouts_ledger_entry, :github_match_reversal,
        stripe_connect_account: @stripe_account,
        sponsors_listing: @listing_with_stripe,
        amount_in_subunits: 20_00
      )

      assert_equal 20_00, @listing_with_stripe.total_match_in_cents
    end

    test "considers ledger entries from across Stripe accounts for fiscally hosted listing" do
      # Have an old inactive Stripe account personally owned by the fiscally hosted listing, where some
      # matching money went:
      inactive_stripe = create(:stripe_connect_account, :inactive, sponsors_listing: @child_listing)
      create(:payouts_ledger_entry, :github_match,
        sponsors_listing: @child_listing,
        stripe_connect_account: inactive_stripe,
        amount_in_subunits: -1_00) # NOTE: these are recorded as a negative value

      # Have more matching money paid into the fiscal host's Stripe, tied to the fiscally hosted listing:
      create(:payouts_ledger_entry, :github_match,
        sponsors_listing: @child_listing,
        stripe_connect_account: @fiscal_host_stripe,
        amount_in_subunits: -3_00)

      assert_equal 4_00, @child_listing.total_match_in_cents
    end

    test "considers ledger entries from across Stripe accounts for non-fiscally hosted listing" do
      # Have an old inactive Stripe account for the listing where some matching money went:
      inactive_stripe = create(:stripe_connect_account, :inactive, sponsors_listing: @listing_with_stripe)
      create(:payouts_ledger_entry, :github_match,
        sponsors_listing: @listing_with_stripe,
        stripe_connect_account: inactive_stripe,
        amount_in_subunits: -1_00) # NOTE: these are recorded as a negative value

      # Have more matching money paid into the active Stripe for the listing:
      create(:payouts_ledger_entry, :github_match,
        sponsors_listing: @listing_with_stripe,
        stripe_connect_account: @stripe_account,
        amount_in_subunits: -3_00)

      assert_equal 4_00, @listing_with_stripe.total_match_in_cents
    end
  end

  context "#stripe_transfer_account_id" do
    test "returns account ID of listing's Stripe account" do
      assert_equal @stripe_account.stripe_account_id,
        @listing_with_stripe.stripe_transfer_account_id
    end

    test "returns nil when listing does not have Stripe account" do
      assert_nil @listing_without_stripe.stripe_transfer_account_id
    end

    test "returns account ID of fiscal host's Stripe account for fiscally hosted listing" do
      assert_equal @fiscal_host_stripe.stripe_account_id,
        @child_listing.stripe_transfer_account_id
    end
  end

  context "#delete_stripe_account" do
    test "returns false when Stripe API call fails" do
      bad_account_id = "acct_8675309jennyjenny"
      stripe_account = create(:stripe_connect_account, stripe_account_id: bad_account_id,
        sponsors_listing: @listing_without_stripe)

      error = assert_no_difference(-> { Billing::StripeConnect::Account.count }) do
        VCR.use_cassette("stripe/failed_account_delete") do
          refute @listing_without_stripe.delete_stripe_account(stripe_account)
        end
      end
    end

    test "returns false when Stripe response does not confirm account was deleted" do
      fake_result = { "deleted" => false }
      fake_response = stub(success?: true, result: fake_result)
      Billing::StripeConnect::Account.any_instance.stubs(:delete_stripe_account).
        returns(fake_response)

      assert_no_difference(-> { Billing::StripeConnect::Account.count }) do
        refute @listing_with_stripe.delete_stripe_account(@stripe_account)
      end
    end

    test "deletes our Stripe account record when the API result succeeds" do
      account_id = "acct_1GPxCJHN2lid8cxK"
      stripe_account = create(:stripe_connect_account, stripe_account_id: account_id,
        sponsors_listing: @listing_without_stripe)

      assert_difference(-> { Billing::StripeConnect::Account.count }, -1) do
        VCR.use_cassette("stripe/delete_account") do
          assert @listing_without_stripe.delete_stripe_account(stripe_account)
        end
      end

      refute Billing::StripeConnect::Account.exists?(stripe_account.id)
    end

    test "wipes Stripe authorization code on the listing" do
      account_id = "acct_1GPxCJHN2lid8cxK"
      listing = create(:sponsors_listing, :approved, stripe_authorization_code: "some-value")
      stripe_account = create(:stripe_connect_account, stripe_account_id: account_id,
        sponsors_listing: listing)

      VCR.use_cassette("stripe/delete_account") do
        assert listing.delete_stripe_account(stripe_account)
      end

      assert_nil listing.reload.stripe_authorization_code
    end

    test "only deletes the specified Stripe account" do
      account_id = "acct_1GPxCJHN2lid8cxK"
      stripe_account = create(:stripe_connect_account, stripe_account_id: account_id,
        sponsors_listing: @listing_without_stripe)
      other_account = create(:stripe_connect_account, :inactive, sponsors_listing: @listing_without_stripe)

      assert_difference(-> { Billing::StripeConnect::Account.count }, -1) do
        VCR.use_cassette("stripe/delete_account") do
          assert @listing_without_stripe.delete_stripe_account(stripe_account)
        end
      end

      refute Billing::StripeConnect::Account.exists?(stripe_account.id)
      assert Billing::StripeConnect::Account.exists?(other_account.id)
    end

    test "errors when given a Stripe account not associated with the listing" do
      rando_stripe_account = create(:stripe_connect_account)

      error = assert_no_difference(-> { Billing::StripeConnect::Account.count }) do
        refute @listing_with_stripe.delete_stripe_account(rando_stripe_account)
      end
    end
  end

  context "#preferred_currency_code" do
    test "returns listing's personal Stripe's default currency" do
      create(:stripe_connect_account, sponsors_listing: @listing_without_stripe, default_currency: "AUD")
      assert_equal "AUD", @listing_without_stripe.preferred_currency_code
    end

    test "returns currency code for listing's billing country when listing has no personal Stripe" do
      @listing_without_stripe.update!(billing_country: "PL")
      assert_equal "PLN", @listing_without_stripe.preferred_currency_code
    end

    test "returns default currency for GitHub when listing has no billing country and no personal Stripe" do
      @listing_without_stripe.update_attribute(:billing_country, nil)
      assert_equal Billing::Money.default_currency, @listing_without_stripe.preferred_currency_code
    end

    test "does not return default currency for fiscal host's Stripe account" do
      currency_not_gh_default = "CAD"
      refute_equal currency_not_gh_default, Billing::Money.default_currency

      @child_listing.update_attribute(:billing_country, nil)
      @fiscal_host_stripe.update!(default_currency: currency_not_gh_default)

      assert_equal Billing::Money.default_currency, @child_listing.preferred_currency_code
    end
  end

  context "#active_stripe_account_balance" do
    test "returns sum of transfer ledger entries made since the last payout" do
      last_payout_at = 1.day.ago
      @listing_with_stripe.update!(last_payout_at: last_payout_at)
      travel_to(2.days.ago) do
        create(:payouts_ledger_entry, :transfer, stripe_connect_account: @stripe_account,
          sponsors_listing: @listing_with_stripe, amount_in_subunits: 5_00)
      end
      create(:payouts_ledger_entry, :transfer, stripe_connect_account: @stripe_account,
        sponsors_listing: @listing_with_stripe, amount_in_subunits: 13_00)
      create(:payouts_ledger_entry, :transfer, stripe_connect_account: @stripe_account,
        sponsors_listing: @listing_with_stripe, amount_in_subunits: 11_00)

      result = @listing_with_stripe.active_stripe_account_balance

      assert_equal Billing::Money.new(24_00, "USD"), result,
        "should only sum transfers made since last payout"
    end

    test "returns sum of transfer ledger entries made since the last payout webhook" do
      last_payout_at = DateTime.new(2019, 7, 16, 19, 31, 23)
      @listing_with_stripe.update!(last_payout_at: last_payout_at)

      travel_to(last_payout_at - 1.day) do
        create(:payouts_ledger_entry, :transfer, stripe_connect_account: @stripe_account,
          sponsors_listing: @listing_with_stripe, amount_in_subunits: 5_00)
      end
      create(:payouts_ledger_entry, :transfer, stripe_connect_account: @stripe_account,
        sponsors_listing: @listing_with_stripe, amount_in_subunits: 13_00)
      create(:payouts_ledger_entry, :transfer, stripe_connect_account: @stripe_account,
        sponsors_listing: @listing_with_stripe, amount_in_subunits: 11_00)

      result = @listing_with_stripe.active_stripe_account_balance

      assert_equal Billing::Money.new(24_00, "USD"), result,
        "should only sum transfers made since last payout"
    end

    test "returns sum of all transfer ledger entries when no last payout is known" do
      @listing_with_stripe.update!(last_payout_at: nil)
      travel_to(2.days.ago) do
        create(:payouts_ledger_entry, :transfer, stripe_connect_account: @stripe_account,
          sponsors_listing: @listing_with_stripe, amount_in_subunits: 5_00)
      end
      create(:payouts_ledger_entry, :transfer, stripe_connect_account: @stripe_account,
        sponsors_listing: @listing_with_stripe, amount_in_subunits: 13_00)
      create(:payouts_ledger_entry, :transfer, stripe_connect_account: @stripe_account,
        sponsors_listing: @listing_with_stripe, amount_in_subunits: 11_00)

      result = @listing_with_stripe.active_stripe_account_balance

      assert_equal Billing::Money.new(29_00, "USD"), result, "should sum all transfers"
    end

    test "subtracts transfer reversals from the sum" do
      @listing_with_stripe.update!(last_payout_at: nil)
      create(:payouts_ledger_entry, :transfer, stripe_connect_account: @stripe_account,
        sponsors_listing: @listing_with_stripe, amount_in_subunits: 15_00)
      create(:payouts_ledger_entry, :transfer_reversal, stripe_connect_account: @stripe_account,
        sponsors_listing: @listing_with_stripe, amount_in_subunits: -5_00)
      create(:payouts_ledger_entry, :transfer, stripe_connect_account: @stripe_account,
        sponsors_listing: @listing_with_stripe, amount_in_subunits: 1_00)

      result = @listing_with_stripe.active_stripe_account_balance

      assert_equal Billing::Money.new(11_00, "USD"), result,
        "should sum transfers and subtract transfer reversals"
    end

    test "returns balances from multiple currencies converted to preferred currency and summed" do
      @stripe_account.update!(default_currency: "PLN", billing_country: "PL")
      @listing_with_stripe.update!(last_payout_at: nil, billing_country: "PL")
      create(:payouts_ledger_entry, :transfer_reversal, stripe_connect_account: @stripe_account,
        sponsors_listing: @listing_with_stripe, amount_in_subunits: -2_00, currency_code: "TRY")
      create(:payouts_ledger_entry, :transfer, stripe_connect_account: @stripe_account,
        sponsors_listing: @listing_with_stripe, amount_in_subunits: 5_00, currency_code: "GEL")
      create(:payouts_ledger_entry, :transfer, stripe_connect_account: @stripe_account,
        sponsors_listing: @listing_with_stripe, amount_in_subunits: 13_00, currency_code: "PLN")
      create(:payouts_ledger_entry, :transfer, stripe_connect_account: @stripe_account,
        sponsors_listing: @listing_with_stripe, amount_in_subunits: 15_00, currency_code: "GEL")
      create(:payouts_ledger_entry, :transfer, stripe_connect_account: @stripe_account,
        sponsors_listing: @listing_with_stripe, amount_in_subunits: 11_00, currency_code: "TRY")

      result = @listing_with_stripe.active_stripe_account_balance

      assert_equal Billing::Money.new(44_19, "PLN"), result
    end

    test "includes balances for specified fiscally hosted listing when checking fiscal host's Stripe" do
      @child_listing.update!(last_payout_at: nil)

      # Make a ledger entry for the fiscal host's Stripe for the fiscally hosted listing we're going
      # to check; should be included in the result:
      create(:payouts_ledger_entry, :transfer, stripe_connect_account: @fiscal_host_stripe,
        sponsors_listing: @child_listing, amount_in_subunits: 15_00)

      # Make a ledger entry for the fiscal host's Stripe but for another fiscally hosted listing;
      # should be excluded from the result:
      other_child_listing = create(:sponsors_listing, :approved, :with_fiscal_host,
        parent_listing: @fiscal_host_listing)
      create(:payouts_ledger_entry, :transfer, stripe_connect_account: @fiscal_host_stripe,
        sponsors_listing: other_child_listing, amount_in_subunits: 30_00)

      # Make a ledger entry for the fiscal host's Stripe but for the fiscal host listing itself;
      # should be excluded from the result:
      create(:payouts_ledger_entry, :transfer, stripe_connect_account: @fiscal_host_stripe,
        sponsors_listing: @fiscal_host_listing, amount_in_subunits: 45_00)

      result = @child_listing.active_stripe_account_balance

      assert_equal Billing::Money.new(15_00, "USD"), result
    end

    test "uses fiscal host's last payout date when checking fiscally hosted listing's Stripe balance" do
      last_fiscal_host_payout_at = DateTime.new(2019, 7, 16, 19, 31, 23)

      @child_listing.update!(last_payout_at: nil)
      @fiscal_host_listing.update!(last_payout_at: last_fiscal_host_payout_at)
      @child_listing.reload

      travel_to(last_fiscal_host_payout_at - 1.day) do
        create(:payouts_ledger_entry, :transfer, stripe_connect_account: @fiscal_host_stripe,
          sponsors_listing: @child_listing, amount_in_subunits: 15_00)
      end

      create(:payouts_ledger_entry, :transfer, stripe_connect_account: @fiscal_host_stripe,
        sponsors_listing: @child_listing, amount_in_subunits: 15_00)

      result = @child_listing.active_stripe_account_balance

      assert_equal Billing::Money.new(15_00, "USD"), result
    end

    # https://github.com/github/sponsors/issues/2601
    test "sums ledger entries made in inactive fiscally hosted listing's Stripe and active fiscal host's Stripe" do
      @child_listing.update!(last_payout_at: nil)

      inactive_child_stripe = create(:stripe_connect_account, :inactive, sponsors_listing: @child_listing)
      create(:payouts_ledger_entry, :transfer, amount_in_subunits: 3_00,
        stripe_connect_account: inactive_child_stripe, sponsors_listing: @child_listing)

      create(:payouts_ledger_entry, :transfer, stripe_connect_account: @fiscal_host_stripe,
        sponsors_listing: @child_listing, amount_in_subunits: 5_00)

      result = @child_listing.active_stripe_account_balance

      assert_equal Billing::Money.new(8_00, "USD"), result
    end

    test "does not sum ledger entry made to fiscal host's inactive Stripe" do
      @child_listing.update!(last_payout_at: nil)

      inactive_parent_stripe = create(:stripe_connect_account, :inactive,
        sponsors_listing: @fiscal_host_listing)
      create(:payouts_ledger_entry, :transfer, amount_in_subunits: 30_00,
        stripe_connect_account: inactive_parent_stripe, sponsors_listing: @child_listing)

      result = @child_listing.active_stripe_account_balance

      assert_equal Billing::Money.new(0, "USD"), result
    end

    test "returns zero balance in currency for listing's billing country when listing has no active Stripe account" do
      @listing_without_stripe.update!(billing_country: "AU")
      assert_equal Billing::Money.new(0, "AUD"),
        @listing_without_stripe.active_stripe_account_balance
    end

    test "returns zero balance when no current ledger entries, using Stripe account's currency when no ledger entries" do
      @stripe_account.update!(default_currency: "pln")
      result = @listing_with_stripe.active_stripe_account_balance
      assert_equal Billing::Money.new(0, "PLN"), result
    end

    test "returns zero balance when no current ledger entries, using currency for billing country when no currency set on Stripe account" do
      @stripe_account.update!(default_currency: nil, billing_country: "GR")
      @listing_with_stripe.update!(billing_country: "GR")

      result = @listing_with_stripe.active_stripe_account_balance

      assert_equal Billing::Money.new(0, "EUR"), result
    end
  end

  context "#active_stripe_account_estimated_last_payout_balance" do
    test "returns nil if no payout webhooks exist" do
      assert_nil @listing_with_stripe.active_stripe_account_estimated_last_payout_balance
    end

    test "returns the sum of all entries in the last payout" do
      travel_to(2.days.ago) do
        create(:stripe_webhook, :payout_created,
          account: @stripe_account.stripe_account_id,
          created: Time.now,
          object: { created: Time.now.to_i },
        )
      end

      travel_to(3.days.ago) do
        create(:payouts_ledger_entry, :transfer, stripe_connect_account: @stripe_account,
          sponsors_listing: @listing_with_stripe, amount_in_subunits: 5_00)
      end

      create(:payouts_ledger_entry, :transfer, stripe_connect_account: @stripe_account,
        sponsors_listing: @listing_with_stripe, amount_in_subunits: 13_00)

      result = @listing_with_stripe.active_stripe_account_estimated_last_payout_balance

      assert_equal Billing::Money.new(5_00, "USD"), result,
        "should only sum transfers made since last payout"
    end

    test "excludes entries from before the previous payout" do
      # previous payout
      travel_to(1.month.ago) do
        create(:stripe_webhook, :payout_created,
          account: @stripe_account.stripe_account_id,
          created: Time.now,
          object: { created: Time.now.to_i },
        )
      end

      # latest payout
      travel_to(2.days.ago) do
        create(:stripe_webhook, :payout_created,
          account: @stripe_account.stripe_account_id,
          created: Time.now,
          object: { created: Time.now.to_i },
        )
      end

      travel_to(2.months.ago) do
        create(:payouts_ledger_entry, :transfer, stripe_connect_account: @stripe_account,
          sponsors_listing: @listing_with_stripe, amount_in_subunits: 17_00)
      end

      travel_to(3.days.ago) do
        create(:payouts_ledger_entry, :transfer, stripe_connect_account: @stripe_account,
          sponsors_listing: @listing_with_stripe, amount_in_subunits: 5_00)
      end

      create(:payouts_ledger_entry, :transfer, stripe_connect_account: @stripe_account,
        sponsors_listing: @listing_with_stripe, amount_in_subunits: 13_00)

      result = @listing_with_stripe.active_stripe_account_estimated_last_payout_balance

      assert_equal Billing::Money.new(5_00, "USD"), result,
        "should only sum transfers made since last payout"
    end
  end

  context "#has_balance_in_stripe?" do
    test "true when the Stripe account has a positive balance" do
      create(:payouts_ledger_entry, :transfer, stripe_connect_account: @stripe_account,
        sponsors_listing: @listing_with_stripe, amount_in_subunits: 162_95)
      assert_predicate @listing_with_stripe, :has_balance_in_stripe?
    end

    test "true when listing uses a fiscal host and the fiscally hosted listing has a positive balance" do
      create(:payouts_ledger_entry, :transfer, stripe_connect_account: @fiscal_host_stripe,
        sponsors_listing: @child_listing, amount_in_subunits: 15_00)
      assert_predicate @child_listing, :has_balance_in_stripe?
    end

    test "false when there is no Stripe account for the listing" do
      refute_predicate @listing_without_stripe, :has_balance_in_stripe?
    end

    test "false when the Stripe account has no transfer entries since their last payout" do
      refute_predicate @listing_with_stripe, :has_balance_in_stripe?
    end

    test "false when specified Stripe account does not have a positive balance" do
      # Create a positive balance in another Stripe account owned by the same listing:
      create(:payouts_ledger_entry, :transfer, stripe_connect_account: @stripe_account,
        sponsors_listing: @listing_with_stripe, amount_in_subunits: 162_95)

      other_stripe = create(:stripe_connect_account, :inactive, sponsors_listing: @listing_with_stripe)
      refute @listing_with_stripe.has_balance_in_stripe?(other_stripe)
    end

    test "false when transfer entries since the last payout have a zero sum" do
      create(:payouts_ledger_entry, :transfer, stripe_connect_account: @stripe_account,
        sponsors_listing: @listing_with_stripe, amount_in_subunits: 5_00)
      create(:payouts_ledger_entry, :transfer_reversal, stripe_connect_account: @stripe_account,
        sponsors_listing: @listing_with_stripe, amount_in_subunits: -5_00)
      refute_predicate @listing_with_stripe, :has_balance_in_stripe?
    end
  end

  context "#create_stripe_account!" do
    test "calls the Stripe API with the expected parameters for users" do
      sponsorable = @listing_without_stripe.sponsorable
      api_response_stub = stub(id: "acct_1234")

      ::Stripe::Account.expects(:create).with(equals(
        type: "express",
        email: @listing_without_stripe.contact_email_address,
        business_type: "individual",
        settings: {
          payouts: {
            schedule: { interval: "manual" },
          },
        },
        metadata: {
          stafftools_url: "http://#{GitHub.host_name}/stafftools/sponsors/find_listing/#{@listing_without_stripe.id}"
        },
        additional_verifications: {
          us_w8_or_w9: {
            requested: true,
            upfront: [{ disables: "payouts_and_payments" }],
            w8: { type: :substitute }
          }
        }
      )).returns(api_response_stub)

      account = @listing_without_stripe.create_stripe_account!

      assert_equal api_response_stub.id, account.stripe_account_id
      assert_predicate account, :active?
      assert_equal @listing_without_stripe.id, account["sponsors_listing_id"]
    end

    test "calls the Stripe API with the expected parameters for organizations" do
      org = create(:organization, :sponsorable,
        created_at: (SponsorsListing::MANUAL_PAYOUT_NEW_USER_THRESHOLD + 1.hour).ago,
      )
      listing = org.sponsors_listing
      api_response_stub = stub(id: "acct_1234")

      ::Stripe::Account.expects(:create).with(equals(
        type: "express",
        email: listing.contact_email_address,
        business_type: "company",
        settings: {
          payouts: {
            schedule: { interval: "manual" },
          },
        },
        metadata: {
          stafftools_url: "http://#{GitHub.host_name}/stafftools/sponsors/find_listing/#{listing.id}"
        },
        additional_verifications: {
          us_w8_or_w9: {
            requested: true,
            upfront: [{ disables: "payouts_and_payments" }],
            w8: { type: :substitute }
          }
        }
      )).returns(api_response_stub)

      account = listing.create_stripe_account!

      assert_equal api_response_stub.id, account.stripe_account_id
      assert_predicate account, :active?
      assert_equal listing.id, account["sponsors_listing_id"]
    end

    test "calls the Stripe API with manual payouts when listing is in probation" do
      sponsorable = @listing_without_stripe.sponsorable
      @listing_without_stripe.update!(joined_at: SponsorsListing::JOINED_WAITLIST_MATCH_DEADLINE - 1.day)
      api_response_stub = stub(id: "acct_1234")

      ::Stripe::Account.expects(:create).with(equals(
        type: "express",
        email: @listing_without_stripe.contact_email_address,
        business_type: "individual",
        settings: {
          payouts: {
            schedule: { interval: "manual" },
          },
        },
        metadata: {
          stafftools_url: "http://#{GitHub.host_name}/stafftools/sponsors/find_listing/#{@listing_without_stripe.id}"
        },
        additional_verifications: {
          us_w8_or_w9: {
            requested: true,
            upfront: [{ disables: "payouts_and_payments" }],
            w8: { type: :substitute }
          }
        }
      )).returns(api_response_stub)

      account = @listing_without_stripe.create_stripe_account!

      assert_equal api_response_stub.id, account.stripe_account_id
      assert_predicate account, :active?
      assert_equal @listing_without_stripe.id, account["sponsors_listing_id"]
    end

    test "calls the Stripe API with 'substitute' us_w8_or_w9 additional verification" do
      sponsorable = @listing_without_stripe.sponsorable

      api_response_stub = stub(id: "acct_1234")

      ::Stripe::Account.expects(:create).with(equals(
        type: "express",
        email: @listing_without_stripe.contact_email_address,
        business_type: "individual",
        settings: {
          payouts: {
            schedule: { interval: "manual" },
          },
        },
        metadata: {
          stafftools_url: "http://#{GitHub.host_name}/stafftools/sponsors/find_listing/#{@listing_without_stripe.id}"
        },
        additional_verifications: {
          us_w8_or_w9: {
            requested: true,
            upfront: [
              { disables: "payouts_and_payments" },
            ],
            w8: {
              type: :substitute,
            }
          }
        }
      )).returns(api_response_stub)

      account = @listing_without_stripe.create_stripe_account!

      assert_equal api_response_stub.id, account.stripe_account_id
      assert_predicate account, :active?
      assert_equal @listing_without_stripe.id, account["sponsors_listing_id"]
    end

    test "returns an inactive account if listing already has an active one" do
      api_response_stub = stub(id: "acct_1234")

      ::Stripe::Account.expects(:create).returns(api_response_stub)

      account = @listing_with_stripe.create_stripe_account!

      assert_equal api_response_stub.id, account.stripe_account_id
      refute_predicate account, :active?
      assert_equal @listing_with_stripe.id, account["sponsors_listing_id"]
    end

    test "emits a Hydro event for adding an active Stripe account to a listing that doesn't yet have one" do
      sponsorable = @listing_without_stripe.sponsorable
      api_response_stub = stub(id: "acct_1234")

      ::Stripe::Account.expects(:create).with(equals(
        type: "express",
        email: @listing_without_stripe.contact_email_address,
        business_type: "individual",
        settings: {
          payouts: {
            schedule: { interval: "manual" },
          },
        },
        metadata: {
          stafftools_url: "http://#{GitHub.host_name}/stafftools/sponsors/find_listing/#{@listing_without_stripe.id}"
        },
        additional_verifications: {
          us_w8_or_w9: {
            requested: true,
            upfront: [{ disables: "payouts_and_payments" }],
            w8: { type: :substitute }
          }
        }
      )).returns(api_response_stub)

      account = @listing_without_stripe.create_stripe_account!

      assert_hydro_messages(count: 1, schema: "github.sponsors.v1.StripeConnectAccountCreate")
      assert_hydro_published({
        request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
        sponsors_listing: Hydro::EntitySerializer.sponsors_listing(@listing_without_stripe),
        sponsorable: Hydro::EntitySerializer.user(@listing_without_stripe.sponsorable),
        stripe_connect_account: Hydro::EntitySerializer.stripe_connect_account(account),
        sponsors_listing_stafftools_metadata: Hydro::EntitySerializer
          .sponsors_listing_stafftools_metadata(@listing_without_stripe.stafftools_metadata),
      }, schema: "github.sponsors.v1.StripeConnectAccountCreate")
    end
  end

  context "#destroy" do
    # https://github.com/github/sponsors/issues/3073
    test "do not delete Stripe Connect account from the database when listing is destroyed" do
      assert_difference(-> { SponsorsListing.count }, -1) do
        assert_no_difference(-> { Billing::StripeConnect::Account.including_deleted.count }) do
          @listing_with_stripe.destroy!
        end
      end
    end

    # https://github.com/github/sponsors/issues/3361
    test "sets Stripe Connect account deleted_at when listing is destroyed" do
      refute_predicate @stripe_account, :deleted?
      @listing_with_stripe.destroy!
      assert_predicate @stripe_account.reload, :deleted?
    end
  end
end
