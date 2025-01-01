# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::StripeConnect::AccountTest < GitHub::BillingTestCase
  include HydroTestHelpers

  fixtures do
    @user = create(:user, :sponsorable)
  end

  context "#with_lock" do
    test "raises an exception when trying to lock and the lock is already in use" do
      stripe_account = create(:stripe_connect_account, payouts_enabled: true,
        sponsors_listing: @user.sponsors_listing)
      enable_feature_flag(:stripe_connect_account_lock, @user)

      stripe_account.with_lock do
        assert_raises(GitHub::Restraint::UnableToLock) do
          stripe_account.with_lock do
            stripe_account.update!(payouts_enabled: false)
          end
        end
      end

      assert_predicate stripe_account.reload, :payouts_enabled?,
        "should not have made change to account inside lock block when there was contention"
    end

    test "does not lock when feature is disabled" do
      disable_feature_flag(:stripe_connect_account_lock)
      stripe_account = create(:stripe_connect_account, payouts_enabled: true,
        sponsors_listing: @user.sponsors_listing)

      stripe_account.with_lock do
        assert_nothing_raised do
          stripe_account.with_lock do
            stripe_account.update!(payouts_enabled: false)
          end
        end
      end

      refute_predicate stripe_account.reload, :payouts_enabled?
    end

    test "lock is per Stripe account" do
      stripe_account1 = create(:stripe_connect_account, :inactive, sponsors_listing: @user.sponsors_listing)
      stripe_account2 = create(:stripe_connect_account, payouts_enabled: true,
        sponsors_listing: @user.sponsors_listing)
      enable_feature_flag(:stripe_connect_account_lock, @user)

      stripe_account1.with_lock do
        assert_nothing_raised do
          stripe_account2.with_lock do
            stripe_account2.update!(payouts_enabled: false)
          end
        end
      end

      refute_predicate stripe_account2.reload, :payouts_enabled?
    end

    test "lock is released when block is exited" do
      stripe_account = create(:stripe_connect_account, payouts_enabled: true,
        sponsors_listing: @user.sponsors_listing)
      enable_feature_flag(:stripe_connect_account_lock, @user)

      block_result = stripe_account.with_lock { "foo" }
      assert_equal "foo", block_result

      assert_nothing_raised do
        stripe_account.with_lock do
          stripe_account.update!(payouts_enabled: false)
        end
      end

      refute_predicate stripe_account.reload, :payouts_enabled?
    end
  end

  context ".ga_regions_names" do
    test "includes names of supported countries" do
      assert_includes Billing::StripeConnect::Account::SUPPORTED_COUNTRIES, "US", "need a supported country code"
      assert_includes Billing::StripeConnect::Account::SUPPORTED_COUNTRIES, "ES", "need a supported country code"

      result = Billing::StripeConnect::Account.ga_regions_names

      assert_includes result, "United States of America"
      assert_includes result, "Spain"
    end

    test "does not include names of unsupported countries" do
      refute_includes Billing::StripeConnect::Account::SUPPORTED_COUNTRIES, "NK", "need an unsupported country code"
      refute_includes Billing::StripeConnect::Account::SUPPORTED_COUNTRIES, "CN", "need an unsupported country code"

      result = Billing::StripeConnect::Account.ga_regions_names

      refute_includes result, "North Korea"
      refute_includes result, "China"
    end

    test "replaces some names" do
      alpha2 = "HK"
      assert_includes Billing::StripeConnect::Account::SUPPORTED_COUNTRIES, alpha2
      original_name = Braintree::Address::CountryNames.detect { |_, code, _, _| code == alpha2 }[0]
      refute_nil original_name
      expected_replacement = Billing::StripeConnect::Account::GA_REGION_NAME_REPLACEMENTS[original_name]
      assert_predicate expected_replacement, :present?

      result = Billing::StripeConnect::Account.ga_regions_names

      assert_includes result, expected_replacement
      refute_includes result, original_name, "expected only our translation to be included"
    end
  end

  context "inactive scope" do
    test "includes only Stripe Connect accounts that aren't the active one for their Sponsors listing" do
      active_account = create(:stripe_connect_account)
      inactive_account = create(:stripe_connect_account, :inactive)

      result = Billing::StripeConnect::Account.inactive.where(id: [active_account.id, inactive_account.id])

      assert_includes result, inactive_account
      refute_includes result, active_account
    end
  end

  context "#truncated_stripe_account_id" do
    test "returns a truncated version of the stripe_account_id, truncated in the middle" do
      stripe_account = Billing::StripeConnect::Account.new(stripe_account_id: "acct_1JrlPo2SpoyPkZMW")
      assert_equal "1JrlP…PkZMW", stripe_account.truncated_stripe_account_id
    end

    test "does not elide an already short stripe_account_id" do
      stripe_account = Billing::StripeConnect::Account.new(stripe_account_id: "acct_1JrlPo2Spo")
      assert_equal "1JrlPo2Spo", stripe_account.truncated_stripe_account_id
    end
  end

  context "#datadog_tags" do
    test "returns a list of strings to use for DataDog metrics" do
      stripe_account = build(:stripe_connect_account, :inactive, email: "foo@example.com",
        verification_status: :unverified_no_transfers_capability)

      result = stripe_account.datadog_tags

      assert_same_elements ["payable_type:SponsorsListing", "active:false", "has_email:true",
        "verification_status:unverified_no_transfers_capability"], result
    end
  end

  context "#instrument_link_account" do
    test "creates an audit log event with details of the Stripe account and the Sponsors listing" do
      actor = create(:staff_admin_user)
      sponsorable = create(:user, :verified)
      sponsors_listing = create(:sponsors_listing, sponsorable: sponsorable)
      stripe_account = create(:stripe_connect_account, :unverified, sponsors_listing: sponsors_listing, country: "US",
        billing_country: "CA", payouts_enabled: true, charges_enabled: true, requirements_past_due: false,
        tax_reporting_capability: false, card_payments_capability: false, transfers_capability: false,
        requirements_currently_due: false, requirements_eventually_due: false, active: true, default_currency: "usd",
        current_requirements_deadline: 1.week.from_now, details_submitted: true,
        payout_interval: "manual", disabled_reason: nil)
      expected_payload = {
        active: true,
        verified: false,
        payouts_enabled: true,
        details_submitted: true,
        charges_enabled: true,
        requirements_past_due: false,
        current_requirements_deadline: stripe_account.current_requirements_deadline,
        tax_reporting_capability: false,
        card_payments_capability: false,
        transfers_capability: false,
        requirements_currently_due: false,
        requirements_eventually_due: false,
        stripe_connect_account: stripe_account.stripe_account_id,
        stripe_connect_account_id: stripe_account.id,
        sponsors_listing_id: sponsors_listing.id,
        sponsors_listing: sponsors_listing.slug,
        country: "US",
        billing_country: "CA",
        user: sponsorable.login,
        user_id: sponsorable.id,
        email: stripe_account.email,
        default_currency: "usd",
        disabled_reason: nil,
        payout_interval: "manual",
      }.merge(GitHub.guarded_audit_log_staff_actor_entry(actor))
      events = subscribe("stripe_connect_account.link_account")

      stripe_account.instrument_link_account(actor)

      refute_nil event = events.pop, "an event was expected"
      assert_equal expected_payload, event.payload
    end
  end

  context "#unverified_explanation" do
    test "returns nil when verified" do
      account = build(:stripe_connect_account, verification_status: :verified)
      assert_nil account.unverified_explanation
    end

    test "returns a string when unverified due to past-due requirements" do
      account = build(:stripe_connect_account, :unverified, requirements_past_due: true)
      assert_equal "Identity items past due", account.unverified_explanation
    end

    test "returns a string when unverified due to currently due requirements" do
      account = build(:stripe_connect_account, :unverified, requirements_currently_due: true)
      assert_equal "Identity items due", account.unverified_explanation
    end

    test "returns a string when unverified due to details having not been submitted" do
      account = build(:stripe_connect_account, verification_status: :unverified_details_not_submitted)
      assert_equal "Account details haven't been submitted", account.unverified_explanation
    end

    test "returns a string when unverified due to not having the transfers capability" do
      account = build(:stripe_connect_account, verification_status: :unverified_no_transfers_capability)
      assert_equal "Account not configured to allow transfers", account.unverified_explanation
    end

    test "returns a string when unverified due to not having the tax reporting capability" do
      account = build(:stripe_connect_account, verification_status: :unverified_no_tax_reporting_capability)
      assert_equal "Account not configured to support tax reporting", account.unverified_explanation
    end

    test "returns a string when unverified due to not having the card payments capability" do
      account = build(:stripe_connect_account, verification_status: :unverified_no_card_payments_capability)
      assert_equal "Account not configured to allow card payments", account.unverified_explanation
    end

    test "returns a string when unverified and the reason isn't clear" do
      account = build(:stripe_connect_account, verification_status: :unknown)
      assert_equal "Missing details in Stripe Connect account", account.unverified_explanation
    end
  end

  context "validation" do
    test "requires a Sponsors listing association" do
      account = build(:stripe_connect_account, sponsors_listing: nil)
      refute_predicate account, :valid?
    end

    test "requires a stripe account ID" do
      account = build(:stripe_connect_account, stripe_account_id: nil)
      refute account.valid?
    end

    test "requires a unique stripe account ID" do
      create(:stripe_connect_account, stripe_account_id: "acct_h3wwosm0lb34n")
      account = build(:stripe_connect_account, stripe_account_id: "acct_h3wwosm0lb34n")
      refute account.valid?
    end

    test "only one active account can exist per Sponsors listing" do
      existing_active_account = create(:stripe_connect_account)
      new_active_account = build(:stripe_connect_account, sponsors_listing: existing_active_account.sponsors_listing)

      refute_predicate new_active_account, :valid?
      assert_includes new_active_account.errors[:sponsors_listing_id], "already has an active Stripe Connect account"
    end

    test "multiple inactive accounts can exist per Sponsors listing" do
      existing_active_account = create(:stripe_connect_account)
      listing = existing_active_account.sponsors_listing
      existing_inactive_account = create(:stripe_connect_account, :inactive, sponsors_listing: listing)
      new_inactive_account = build(:stripe_connect_account, :inactive, sponsors_listing: listing)

      assert_predicate new_inactive_account, :valid?
    end

    test "limits total number of accounts per Sponsors listing on creation of a new Stripe account" do
      existing_active_account = create(:stripe_connect_account)
      listing = existing_active_account.sponsors_listing
      existing_inactive_account = create(:stripe_connect_account, :inactive, sponsors_listing: listing)

      Billing::StripeConnect::Account.stub_const(:MAX_ACCOUNTS_PER_SPONSORS_LISTING, 2) do
        new_inactive_account = build(:stripe_connect_account, :inactive, sponsors_listing: listing)

        refute_predicate new_inactive_account, :valid?
        assert_includes new_inactive_account.errors[:sponsors_listing_id],
          "has reached the limit for Stripe Connect accounts"
      end
    end

    # https://github.com/github/sponsors/issues/4627
    test "does not error when Sponsors listing exceeds Stripe account limit when updating an existing Stripe account" do
      existing_active_account = create(:stripe_connect_account)
      listing = existing_active_account.sponsors_listing
      existing_inactive_account = create(:stripe_connect_account, :inactive, sponsors_listing: listing)
      over_the_limit_account = create(:stripe_connect_account, :inactive, sponsors_listing: listing)

      Billing::StripeConnect::Account.stub_const(:MAX_ACCOUNTS_PER_SPONSORS_LISTING, 2) do
        over_the_limit_account.w8_or_w9_requested_at = Time.now
        assert_predicate over_the_limit_account, :valid?
      end
    end
  end

  context "#sponsorable_id" do
    test "returns the sponsorable ID" do
      sponsors_listing = create(:sponsors_listing)
      stripe_account = create(:stripe_connect_account, sponsors_listing: sponsors_listing)
      assert_equal sponsors_listing.sponsorable_id, stripe_account.sponsorable_id
    end
  end

  context "#w8_or_w9_verification_required?" do
    test "returns true if the w8/9 form was requested" do
      stripe_account = create(:stripe_connect_account, w8_or_w9_requested_at: Time.now)
      assert_predicate stripe_account, :w8_or_w9_verification_required?
    end

    test "returns false if the w8/9 form was not requested" do
      stripe_account = create(:stripe_connect_account)
      refute_predicate stripe_account, :w8_or_w9_verification_required?
    end
  end

  context "#async_adminable_by?" do
    test "returns true if actor is the account's Sponsors listing's sponsorable" do
      sponsorable = create(:user)
      rando = create(:user)
      listing = create(:sponsors_listing, sponsorable: sponsorable)
      stripe_account = create(:stripe_connect_account, sponsors_listing: listing)

      assert stripe_account.async_adminable_by?(sponsorable).sync
      refute stripe_account.async_adminable_by?(rando).sync
    end

    test "returns true only if user is the account's Sponsors listing's org's admin" do
      org = create(:organization)
      rando = create(:user)
      billing_manager = create(:user)
      org_member = create(:user)

      org.add_member(org_member)
      org.billing.add_manager(billing_manager, actor: org.admin)

      listing = create(:sponsors_listing, sponsorable: org)
      stripe_account = create(:stripe_connect_account, sponsors_listing: listing)

      assert stripe_account.async_adminable_by?(org.admin).sync
      refute stripe_account.async_adminable_by?(rando).sync
      refute stripe_account.async_adminable_by?(billing_manager).sync
      refute stripe_account.async_adminable_by?(org_member).sync
    end

    test "returns false for nil viewer" do
      stripe_account = create(:stripe_connect_account)
      refute stripe_account.async_adminable_by?(nil).sync
    end
  end

  context "#belongs_to?" do
    test "returns true when the given user is the Sponsors listing maintainer" do
      account = create(:stripe_connect_account)
      user = account.sponsorable

      assert account.belongs_to?(user)
    end

    test "returns false for random user" do
      account = create(:stripe_connect_account)
      user = create(:user)

      refute account.belongs_to?(user)
    end

    test "returns true when the given user can manage the Sponsors listing org" do
      org = create(:organization, :sponsorable)
      account = create(:stripe_connect_account, sponsors_listing: org.sponsors_listing)
      user = org.admin

      assert account.belongs_to?(user)
    end

    test "returns false for random user on orgs" do
      org = create(:organization, :sponsorable)
      account = create(:stripe_connect_account, sponsors_listing: org.sponsors_listing)
      user = create(:user)

      refute account.belongs_to?(user)
    end
  end

  context "#deletable_by?" do
    test "returns false for the sponsorable when the account is active and the sponsors listing is approved" do
      stripe_connect_account = create(:stripe_connect_account, :approved_listing)
      sponsorable = stripe_connect_account.sponsorable

      refute stripe_connect_account.deletable_by?(sponsorable)
    end

    test "returns false for a staff member when the account is active and the sponsors listing is approved" do
      stripe_connect_account = create(:stripe_connect_account, :approved_listing)
      staff = create(:user, :staff)

      refute stripe_connect_account.deletable_by?(staff)
    end

    test "returns false for the sponsorable when the account has balance in stripe" do
      stripe_connect_account = create(:stripe_connect_account, :inactive, stripe_account_id: "acct_1Ep35IFxJZYbadPl")
      sponsors_listing       = stripe_connect_account.sponsors_listing
      sponsorable            = sponsors_listing.sponsorable
      create(:payouts_ledger_entry, :transfer, stripe_connect_account: stripe_connect_account,
        sponsors_listing: sponsors_listing, amount_in_subunits: 162_95)

      VCR.use_cassette("stripe/retrieve_balance") do
        refute stripe_connect_account.deletable_by?(sponsorable)
      end
    end

    test "returns false for a staff member when the account has balance in stripe" do
      stripe_connect_account = create(:stripe_connect_account, :inactive, stripe_account_id: "acct_1Ep35IFxJZYbadPl")
      sponsors_listing       = stripe_connect_account.sponsors_listing
      staff                  = create(:user, :staff)
      create(:payouts_ledger_entry, :transfer, stripe_connect_account: stripe_connect_account,
        sponsors_listing: sponsors_listing, amount_in_subunits: 162_95)

      VCR.use_cassette("stripe/retrieve_balance") do
        refute stripe_connect_account.deletable_by?(staff)
      end
    end

    test "returns false for the sponsorable when the account has received money" do
      stripe_connect_account = create(:stripe_connect_account, :inactive, stripe_account_id: "acct_1Ep35IFxJZYbadPl")
      sponsors_listing       = stripe_connect_account.sponsors_listing
      sponsorable            = sponsors_listing.sponsorable
      create(:payouts_ledger_entry, :transfer, stripe_connect_account: stripe_connect_account,
        sponsors_listing: sponsors_listing, amount_in_subunits: 162_95)
      create(:payouts_ledger_entry, :transfer, stripe_connect_account: stripe_connect_account,
        sponsors_listing: sponsors_listing, amount_in_subunits: -162_95)

      VCR.use_cassette("stripe/retrieve_balance") do
        refute stripe_connect_account.deletable_by?(sponsorable)
      end
    end

    test "returns true for a staff member when the account has received money" do
      stripe_connect_account = create(:stripe_connect_account, :inactive, stripe_account_id: "acct_1Ep35IFxJZYbadPl")
      sponsors_listing       = stripe_connect_account.sponsors_listing
      staff                  = create(:user, :staff)
      create(:payouts_ledger_entry, :transfer, stripe_connect_account: stripe_connect_account,
        sponsors_listing: sponsors_listing, amount_in_subunits: 162_95)
      create(:payouts_ledger_entry, :transfer, stripe_connect_account: stripe_connect_account,
        sponsors_listing: sponsors_listing, amount_in_subunits: -162_95)

      VCR.use_cassette("stripe/retrieve_balance") do
        assert stripe_connect_account.deletable_by?(staff)
      end
    end

    test "returns true for the sponsorable when the account is inactive and never received money before" do
      stripe_connect_account = create(:stripe_connect_account, :inactive, stripe_account_id: "acct_1GWDFWEFOWQtls2W")
      sponsorable = stripe_connect_account.sponsorable

      VCR.use_cassette("stripe/retrieve_balance_and_delete_account") do
        assert stripe_connect_account.deletable_by?(sponsorable)
      end
    end

    test "returns true for a staff member when the account is inactive and never received money before" do
      stripe_connect_account = create(:stripe_connect_account, :inactive, stripe_account_id: "acct_1GWDFWEFOWQtls2W")
      staff = create(:user, :staff)

      VCR.use_cassette("stripe/retrieve_balance_and_delete_account") do
        assert stripe_connect_account.deletable_by?(staff)
      end
    end
  end

  context "#reason_delete_is_not_allowed?" do
    test "returns :active_account when the account is active and the sponsors listing is approved" do
      stripe_connect_account = create(:stripe_connect_account, :approved_listing)

      assert_equal :active_account, stripe_connect_account.reason_delete_is_not_allowed
    end

    test "returns :positive_balance when the account has balance in stripe" do
      stripe_connect_account = create(:stripe_connect_account, :inactive, stripe_account_id: "acct_1Ep35IFxJZYbadPl")
      sponsors_listing       = stripe_connect_account.sponsors_listing
      create(:payouts_ledger_entry, :transfer, stripe_connect_account: stripe_connect_account,
        sponsors_listing: sponsors_listing, amount_in_subunits: 162_95)

      VCR.use_cassette("stripe/retrieve_balance") do
        assert_equal :positive_balance, stripe_connect_account.reason_delete_is_not_allowed
      end
    end

    test "returns :has_received_money when the account has received money" do
      stripe_connect_account = create(:stripe_connect_account, :inactive, stripe_account_id: "acct_1Ep35IFxJZYbadPl")
      sponsors_listing       = stripe_connect_account.sponsors_listing
      create(:payouts_ledger_entry, :transfer, stripe_connect_account: stripe_connect_account,
        sponsors_listing: sponsors_listing, amount_in_subunits: 162_95)
      create(:payouts_ledger_entry, :transfer, stripe_connect_account: stripe_connect_account,
        sponsors_listing: sponsors_listing, amount_in_subunits: -162_95)

      VCR.use_cassette("stripe/retrieve_balance") do
        assert_equal :has_received_money, stripe_connect_account.reason_delete_is_not_allowed
      end
    end

    test "returns nil when the account is inactive and never received money before" do
      stripe_connect_account = create(:stripe_connect_account, :inactive, stripe_account_id: "acct_1GWDFWEFOWQtls2W")

      VCR.use_cassette("stripe/retrieve_balance_and_delete_account") do
        refute stripe_connect_account.reason_delete_is_not_allowed
      end
    end
  end

  context "#delete_stripe_account" do
    test "deletes account on Stripe but not locally" do
      account_id = "acct_1GPxCJHN2lid8cxK"
      stripe_connect_account = create(:stripe_connect_account, stripe_account_id: account_id)

      response = assert_no_difference(-> { Billing::StripeConnect::Account.count }) do
        VCR.use_cassette("stripe/delete_account") do
          stripe_connect_account.delete_stripe_account
        end
      end

      assert_predicate response, :success?
      account_object = response.result
      assert_instance_of Stripe::Account, account_object
      assert_equal account_id, account_object.id
      assert_predicate account_object, :deleted?
      assert account_object["deleted"]
      assert Billing::StripeConnect::Account.exists?(stripe_connect_account.id)
    end
  end

  context "#ledger_entries_for_sponsors_listing" do
    test "includes ledger entry tied to specified Sponsors listing" do
      sponsors_listing = create(:sponsors_listing)
      stripe_account = create(:stripe_connect_account, sponsors_listing: sponsors_listing)
      ledger_entry = create(:payouts_ledger_entry, stripe_connect_account: stripe_account,
        sponsors_listing: sponsors_listing)

      result = stripe_account.ledger_entries_for_sponsors_listing(sponsors_listing)

      assert_includes result, ledger_entry
    end

    test "omits ledger entry that isn't tied to a Sponsors listing" do
      sponsors_listing = create(:sponsors_listing)
      stripe_account = create(:stripe_connect_account, sponsors_listing: sponsors_listing)
      ledger_entry = create(:payouts_ledger_entry, stripe_connect_account: stripe_account)
      ledger_entry.update_attribute(:sponsors_listing_id, nil)

      result = stripe_account.ledger_entries_for_sponsors_listing(sponsors_listing)

      refute_includes result, ledger_entry
    end

    test "omits ledger entry tied to a different Sponsors listing" do
      sponsors_listing = create(:sponsors_listing)
      stripe_account = create(:stripe_connect_account, sponsors_listing: sponsors_listing)
      ledger_entry = create(:payouts_ledger_entry, stripe_connect_account: stripe_account,
        sponsors_listing: sponsors_listing)
      other_listing = create(:sponsors_listing)

      result = stripe_account.ledger_entries_for_sponsors_listing(other_listing)

      refute_includes result, ledger_entry
    end

    test "omits ledger entry for a different Stripe account" do
      sponsors_listing = create(:sponsors_listing)
      stripe_account = create(:stripe_connect_account, sponsors_listing: sponsors_listing)
      other_stripe_account = create(:stripe_connect_account, :inactive, sponsors_listing: sponsors_listing)
      ledger_entry = create(:payouts_ledger_entry, stripe_connect_account: other_stripe_account,
        sponsors_listing: sponsors_listing)

      result = stripe_account.ledger_entries_for_sponsors_listing(sponsors_listing)

      refute_includes result, ledger_entry
    end
  end

  context "#stripe_dashboard_url" do
    test "returns test URL for development" do
      user = create(:user, :sponsorable)
      account = create(:stripe_connect_account, sponsors_listing: user.sponsors_listing)
      url = "https://dashboard.stripe.com/test/connect/accounts/#{account.stripe_account_id}"

      GitHub::AppEnvironment.stubs(:development?).returns(true)
      assert_equal url, account.stripe_dashboard_url
    end

    test "returns prod URL in production" do
      user = create(:user, :sponsorable)
      account = create(:stripe_connect_account, sponsors_listing: user.sponsors_listing)
      url = "https://dashboard.stripe.com/connect/accounts/#{account.stripe_account_id}"

      GitHub::AppEnvironment.stubs(:production?).returns(true)
      assert_equal url, account.stripe_dashboard_url
    end
  end

  context "#country_name" do
    test "without country set" do
      stripe_account = build(:stripe_connect_account, country: nil)
      assert_nil stripe_account.country_name
    end

    test "with country set" do
      stripe_account = build(:stripe_connect_account, country: "BR")
      assert_equal "Brazil", stripe_account.country_name
    end
  end

  context "#billing_country_name" do
    test "without billing_country set" do
      stripe_account = build(:stripe_connect_account, billing_country: nil)
      assert_nil stripe_account.billing_country_name
    end

    test "with billing_country set" do
      stripe_account = build(:stripe_connect_account, billing_country: "CA")
      assert_equal "Canada", stripe_account.billing_country_name
    end
  end

  context "ordered_by_ledger_entry_amount scope" do
    test "sorts accounts with a larger $ amount of transfers first" do
      low_dollar_account = create(:stripe_connect_account)
      high_dollar_account = create(:stripe_connect_account)
      mid_dollar_account = create(:stripe_connect_account)

      # $1.00 for low-dollar account
      create(:payouts_ledger_entry, :transfer, amount_in_subunits: 1_00,
        stripe_connect_account: low_dollar_account)

      # $4.00 for mid-dollar account
      create(:payouts_ledger_entry, :transfer, amount_in_subunits: 2_00,
        stripe_connect_account: mid_dollar_account)
      create(:payouts_ledger_entry, :transfer, amount_in_subunits: 9_00,
        stripe_connect_account: mid_dollar_account)
      create(:payouts_ledger_entry, :transfer_reversal, amount_in_subunits: -7_00,
        stripe_connect_account: mid_dollar_account)

      # $9.00 for high-dollar account
      create(:payouts_ledger_entry, :transfer, amount_in_subunits: 10_00,
        stripe_connect_account: high_dollar_account)
      create(:payouts_ledger_entry, :transfer_reversal, amount_in_subunits: -1_00,
        stripe_connect_account: high_dollar_account)

      result = Billing::StripeConnect::Account.ordered_by_ledger_entry_amount.
        where(id: [low_dollar_account, mid_dollar_account, high_dollar_account])

      assert_equal [high_dollar_account, mid_dollar_account, low_dollar_account],
        result
    end
  end

  context "verified scope" do
    test "returns only accounts with verification_status=verified" do
      verified_account = create(:stripe_connect_account, verification_status: :verified)
      unverified_account1 = create(:stripe_connect_account, verification_status: :unverified)
      unverified_account2 = create(:stripe_connect_account, verification_status: :unverified_requirements_past_due)
      unverified_account3 = create(:stripe_connect_account, verification_status: :unknown)

      result = Billing::StripeConnect::Account.verified.where(id: [
        verified_account, unverified_account1, unverified_account2, unverified_account3
      ])

      assert_includes result, verified_account
      refute_includes result, unverified_account1
      refute_includes result, unverified_account2
      refute_includes result, unverified_account3
    end
  end

  context "#update_from_stripe" do
    test "sets email" do
      account = build(:stripe_connect_account, email: nil)
      assert account.update_from_stripe("email" => "test@example.com")
      assert_equal "test@example.com", account.reload.email
    end

    test "sets default currency" do
      account = build(:stripe_connect_account, default_currency: nil)
      assert account.update_from_stripe("default_currency" => "cad")
      assert_equal "cad", account.reload.default_currency
    end

    test "sets current requirements deadline" do
      account = build(:stripe_connect_account, current_requirements_deadline: nil)
      assert account.update_from_stripe("requirements" => {
        "current_deadline" => 1565640754
      })
      assert_equal Time.at(1565640754), account.reload.current_requirements_deadline
    end

    test "wipes current requirements deadline as necessary" do
      account = build(:stripe_connect_account, current_requirements_deadline: Time.now)
      assert account.update_from_stripe("requirements" => {
        "current_deadline" => nil
      })
      assert_nil account.reload.current_requirements_deadline
    end

    test "sets requirements past due" do
      account = build(:stripe_connect_account, requirements_past_due: false)
      assert account.update_from_stripe("requirements" => {
        "past_due" => ["company.address.state"]
      })
      assert_predicate account.reload, :requirements_past_due?
    end

    test "sets requirements currently due" do
      account = build(:stripe_connect_account, requirements_currently_due: false)
      assert account.update_from_stripe("requirements" => {
        "currently_due" => ["company.address.state"]
      })
      assert_predicate account.reload, :requirements_currently_due?
    end

    test "sets requirements eventually due" do
      account = build(:stripe_connect_account, requirements_eventually_due: false)
      assert account.update_from_stripe("requirements" => {
        "eventually_due" => ["company.address.state"]
      })
      assert_predicate account.reload, :requirements_eventually_due?
    end

    test "sets payout interval" do
      account = build(:stripe_connect_account, payout_interval: nil)
      assert account.update_from_stripe("settings" => {
        "payouts" => {
          "schedule" => { "interval" => "manual" }
        }
      })
      assert_equal "manual", account.reload.payout_interval
    end

    test "sets disabled reason" do
      account = build(:stripe_connect_account, disabled_reason: nil)
      assert account.update_from_stripe("requirements" => {
        "disabled_reason" => "requirements.past_due"
      })
      assert_equal "requirements.past_due", account.reload.disabled_reason
    end

    test "sets billing country" do
      account = build(:stripe_connect_account, billing_country: nil)
      assert account.update_from_stripe("external_accounts" => {
        "data" => [{ "country" => "PT" }]
      }), (account.errors.full_messages + account.sponsors_listing.errors.full_messages).to_sentence
      assert_equal "PT", account.reload.billing_country
    end

    test "wipes billing country when there are no external accounts" do
      account = build(:stripe_connect_account, billing_country: "US")
      assert account.update_from_stripe("external_accounts" => { "data" => [] })
      assert_nil account.reload.billing_country
    end

    test "sets country" do
      account = build(:stripe_connect_account, country: nil)
      assert account.update_from_stripe("country" => "PT"),
        (account.errors.full_messages + account.sponsors_listing.errors.full_messages).to_sentence
      assert_equal "PT", account.reload.country
    end

    test "sets verified to true when status is unverified and there are no currently due requirements" do
      account = build(:stripe_connect_account, :approved_listing, :unverified)
      maintainer = account.sponsorable

      assert account.update_from_stripe(
        "individual" => {
          "verification" => {
            "status" => "unverified"
          }
        },
        "details_submitted" => true,
        "capabilities" => {
          "transfers" => "active",
          "card_payments" => "active"
        },
        "requirements" => { "currently_due" => [], "past_due" => [] }
      )
      assert_predicate account.reload, :verified_verification_status?
    end

    test "sets verified to true when tax_reporting_us_1099_misc capability is active for US account" do
      account = build(:stripe_connect_account, :unverified)
      assert account.update_from_stripe(
        "individual" => {
          "verification" => { "status" => "verified" }
        },
        "country" => "US",
        "details_submitted" => true,
        "capabilities" => {
          "transfers" => "active",
          "card_payments" => "active",
          "tax_reporting_us_1099_misc" => "active"
        },
        "requirements" => { "currently_due" => [], "past_due" => [] }
      ), (account.errors.full_messages + account.sponsors_listing.errors.full_messages).to_sentence
      assert_predicate account, :verified_verification_status?
    end

    # https://github.com/github/sponsors/issues/3965#issuecomment-1212174185
    test "sets verified to true when tax_reporting_us_1099_misc capability is active for non-US account with US bank account" do
      account = build(:stripe_connect_account, :unverified)
      assert account.update_from_stripe(
        "individual" => {
          "verification" => { "status" => "verified" }
        },
        "country" => "PL",
        "external_accounts" => {
          "data" => [{ "country" => "US" }]
        },
        "details_submitted" => true,
        "capabilities" => {
          "transfers" => "active",
          "card_payments" => "active",
          "tax_reporting_us_1099_misc" => "active"
        },
        "requirements" => { "currently_due" => [], "past_due" => [] }
      )
      assert_predicate account, :verified_verification_status?
    end

    test "sets verified to false when tax_reporting_us_1099_misc capability is not active for US account" do
      account = create(:stripe_connect_account, :unverified)
      assert account.update_from_stripe(
        "individual" => {
          "verification" => { "status" => "verified" }
        },
        "country" => "US",
        "details_submitted" => true,
        "capabilities" => {
          "transfers" => "active",
          "card_payments" => "active"
        },
        "requirements" => { "currently_due" => [], "past_due" => [] }
      ), (account.errors.full_messages + account.sponsors_listing.errors.full_messages).to_sentence
      refute_predicate account, :verified_verification_status?
    end

    test "sets verified to false when none of transfers, beneficiary_transfers, platform_payments is active" do
      account = build(:stripe_connect_account, :unverified)
      assert account.update_from_stripe(
        "individual" => {
          "verification" => { "status" => "verified" }
        },
        "details_submitted" => true,
        "capabilities" => { "card_payments" => "active" },
        "requirements" => { "currently_due" => [], "past_due" => [] }
      )
      refute_predicate account, :verified_verification_status?
    end

    # For now, we will allow Japan accounts to use the card_payments capability instead of the transfers capability
    # https://github.com/github/github/pull/231897#issuecomment-1213298472
    test "sets verified to true when a Japanese account has card_payments and not transfers capability" do
      account = build(:stripe_connect_account, :unverified)
      assert account.update_from_stripe(
        "requirements" => { "currently_due" => [], "past_due" => [] },
        "details_submitted" => true,
        "country" => "JP",
        "capabilities" => {
          "card_payments" => "active"
        }
      ), (account.errors.full_messages + account.sponsors_listing.errors.full_messages).to_sentence
      assert_predicate account.reload, :verified_verification_status?
    end

    test "sets verified to true when status is not given and there are no currently due requirements" do
      account = build(:stripe_connect_account, :unverified)
      assert account.update_from_stripe(
        "requirements" => { "currently_due" => [], "past_due" => [] },
        "details_submitted" => true,
        "capabilities" => {
          "transfers" => "active",
          "card_payments" => "active"
        }
      )
      assert_predicate account, :verified_verification_status?
    end

    # https://github.com/github/sponsors/issues/3440
    test "sets verified to true when there are only eventually due requirements" do
      account = build(:stripe_connect_account, :unverified)
      assert account.update_from_stripe(
        "individual" => {
          "verification" => {
            "status" => "verified"
          }
        },
        "capabilities" => {
          "transfers" => "active",
          "card_payments" => "active"
        },
        "details_submitted" => true,
        "requirements" => { "eventually_due" => ["individual.address.city"], "past_due" => [] }
      )
      assert_predicate account, :verified_verification_status?
    end

    test "sets verified to false when there are currently due requirements with a deadline" do
      account = build(:stripe_connect_account, :unverified)
      assert account.update_from_stripe(
        "individual" => {
          "verification" => {
            "status" => "verified"
          }
        },
        "capabilities" => {
          "transfers" => "active",
          "card_payments" => "active"
        },
        "details_submitted" => true,
        "requirements" => {
          :"current_deadline" => 1565640754,
          "currently_due" => ["company.address.state"],
          "past_due" => [],
        }
      )
      refute_predicate account, :verified_verification_status?
    end

    test "sets verified to true when there are currently due requirements without a deadline" do
      account = build(:stripe_connect_account, :unverified)
      assert account.update_from_stripe(
        "individual" => {
          "verification" => {
            "status" => "verified"
          }
        },
        "capabilities" => {
          "transfers" => "active",
          "card_payments" => "active"
        },
        "details_submitted" => true,
        "requirements" => {
          :"current_deadline" => nil,
          "currently_due" => ["company.address.state"],
          "past_due" => [],
        }
      )
      assert_predicate account, :verified_verification_status?
    end

    test "sets charges enabled" do
      account = build(:stripe_connect_account, charges_enabled: false)
      assert account.update_from_stripe("charges_enabled" => true)
      assert_equal true, account.reload.charges_enabled
      assert_predicate account, :charges_enabled?
    end

    test "sets payouts enabled" do
      account = build(:stripe_connect_account, payouts_enabled: false)
      assert account.update_from_stripe("payouts_enabled" => true)
      assert_equal true, account.reload.payouts_enabled
      assert_predicate account, :payouts_enabled?
    end

    test "sets details_submitted" do
      account = create(:stripe_connect_account, details_submitted: false)
      assert account.update_from_stripe("details_submitted" => true)
      assert_equal true, account.reload.details_submitted
      assert_predicate account, :details_submitted?
    end

    test "sets transfers_capability" do
      account = create(:stripe_connect_account, transfers_capability: false)
      assert account.update_from_stripe("capabilities" => { "transfers" => "active" })
      assert_equal true, account.reload.transfers_capability
      assert_predicate account, :transfers_capability?
    end

    test "sets card_payments_capability" do
      account = create(:stripe_connect_account, card_payments_capability: false)
      assert account.update_from_stripe("capabilities" => { "card_payments" => "active" })
      assert_equal true, account.reload.card_payments_capability
      assert_predicate account, :card_payments_capability?
    end

    test "sets tax_reporting_capability from tax_reporting_us_1099_misc capability" do
      account = create(:stripe_connect_account, tax_reporting_capability: false)
      assert account.update_from_stripe("capabilities" => {
        "tax_reporting_us_1099_misc" => "active",
      })
      assert_equal true, account.reload.tax_reporting_capability
      assert_predicate account, :tax_reporting_capability?
    end

    test "sets the w8_or_w9_requested_at" do
      account = build(:stripe_connect_account, w8_or_w9_requested_at: nil)
      assert account.update_from_stripe("additional_verifications" => {
        "us_w8_or_w9" => {
          "requested_at" => 1565640754
        }
      })
      assert_equal Time.at(1565640754), account.reload.w8_or_w9_requested_at
    end

    test "wipes w8_or_w9_requested_at when nil" do
      account = build(:stripe_connect_account, w8_or_w9_requested_at: Time.now)
      assert account.update_from_stripe("additional_verifications" => {
        "us_w8_or_w9" => {
          "requested_at" => nil
        }
      })
      assert_nil account.reload.w8_or_w9_requested_at
    end

    test "sets the w8_or_w9_verified to true when status is verified" do
      account = build(:stripe_connect_account, w8_or_w9_verified: Time.now)
      assert account.update_from_stripe("additional_verifications" => {
        "us_w8_or_w9" => {
          "status" => "verified"
        }
      })
      assert_predicate account.reload, :w8_or_w9_verified?
    end

    test "sets the w8_or_w9_verified to false when status is not verified" do
      account = build(:stripe_connect_account, w8_or_w9_verified: Time.now)
      assert account.update_from_stripe("additional_verifications" => {
        "us_w8_or_w9" => {
          "status" => "unverified"
        }
      })
      refute_predicate account.reload, :w8_or_w9_verified?
    end

    test "no-op when given a blank hash" do
      account = create(:stripe_connect_account)
      Billing::StripeConnect::Account.any_instance.expects(:save).never
      assert account.update_from_stripe({})
    end
  end

  context "payouts_enabled scope" do
    test "includes accounts that have payouts enabled in their Stripe details" do
      payouts_enabled_account = create(:stripe_connect_account, payouts_enabled: true)
      assert_predicate payouts_enabled_account, :payouts_enabled?
      payouts_disabled_account = create(:stripe_connect_account, :payouts_disabled)
      all_accounts = [payouts_enabled_account, payouts_disabled_account]

      result = Billing::StripeConnect::Account.where(id: all_accounts).payouts_enabled

      assert_includes result, payouts_enabled_account
      refute_includes result, payouts_disabled_account
    end
  end

  context "#stripe_transactions_for_payout" do
    test "returns transactions for a payout" do
      account = create(:stripe_connect_account, stripe_account_id: "acct_1IziWM2Q3WKZykUd")

      response = VCR.use_cassette("stripe/list_balance_transactions") do
        account.stripe_transactions_for_payout("po_1J4bWv2Q3WKZykUdVvKsPWRE")
      end

      assert_predicate response, :success?
      result = response.result

      refute_empty result.data
      assert result.data.all? { |x| x.is_a?(Stripe::BalanceTransaction) },
        "expected result to be a list of Stripe::Transfer objects"
      assert_same_elements %w[tr_1IzjSREQsq43iHhXCGBqgu1p tr_1IzipFEQsq43iHhXqQ6OzE10],
        result.data.map { |txn| txn.source.source_transfer.id }
    end
  end

  context "#activate" do
    test "marks the account as active and marks existing active account as inactive for the same Sponsors listing" do
      listing = @user.sponsors_listing
      stripe_account1 = create(:stripe_connect_account, sponsors_listing: listing)
      stripe_account2 = create(:stripe_connect_account, :inactive, sponsors_listing: listing)

      assert stripe_account2.activate

      assert_predicate stripe_account2.reload, :active?
      refute_predicate stripe_account1.reload, :active?
    end

    test "no-op for already active account" do
      stripe_account = create(:stripe_connect_account, sponsors_listing: @user.sponsors_listing)
      assert_predicate stripe_account, :active?

      assert_query_count(0) do
        assert stripe_account.activate
      end

      assert_predicate stripe_account.reload, :active?
    end

    test "emits a Hydro event for a Sponsors Stripe account" do
      listing = @user.sponsors_listing
      stripe_account1 = create(:stripe_connect_account, sponsors_listing: listing)
      stripe_account2 = create(:stripe_connect_account, :inactive, sponsors_listing: listing)

      assert stripe_account2.activate

      assert_hydro_messages(count: 1, schema: "github.sponsors.v1.SponsorsListingActiveStripeConnectAccountSwitch")
      assert_hydro_published({
        request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
        sponsors_listing: Hydro::EntitySerializer.sponsors_listing(listing),
        sponsorable: Hydro::EntitySerializer.user(@user),
        old_active_stripe_connect_account: Hydro::EntitySerializer.stripe_connect_account(stripe_account1),
        new_active_stripe_connect_account: Hydro::EntitySerializer.stripe_connect_account(stripe_account2),
        sponsors_listing_stafftools_metadata: Hydro::EntitySerializer
          .sponsors_listing_stafftools_metadata(listing.stafftools_metadata),
      }, schema: "github.sponsors.v1.SponsorsListingActiveStripeConnectAccountSwitch")
    end
  end

  context "#automated_payouts_disabled?" do
    test "true if payout interval is manual" do
      account = build(:stripe_connect_account, payout_interval: "manual")
      assert_predicate account, :automated_payouts_disabled?
    end

    test "false if payout interval is non-manual" do
      account = build(:stripe_connect_account, payout_interval: "daily")
      refute_predicate account, :automated_payouts_disabled?
    end
  end

  context "#billing_country_supports_monthly_payouts?" do
    test "true for country with supported monthly payouts" do
      account = build(:stripe_connect_account, billing_country: "ES")
      assert_predicate account, :billing_country_supports_monthly_payouts?
    end

    test "false for country with unsupported monthly payouts" do
      account = build(:stripe_connect_account, billing_country: "BR")
      refute_predicate account, :billing_country_supports_monthly_payouts?
    end
  end

  context "#stripe_transfers" do
    test "returns an array of billing stripe transfer records for the associated account_id" do
      destination = "acct_1G61WUJWUR5CcHHA"
      stripe_connect_account = create(:stripe_connect_account, stripe_account_id: destination)

      transfers = VCR.use_cassette("stripe/retrieve_destination_records") do
        stripe_connect_account.stripe_transfers
      end

      assert_equal 11, transfers.length
    end

    test "allows passing in limit" do
      destination = "acct_1G61WUJWUR5CcHHA"
      stripe_connect_account = create(:stripe_connect_account, stripe_account_id: destination)

      transfers = VCR.use_cassette("stripe/retrieve_destination_records_with_limit") do
        stripe_connect_account.stripe_transfers(limit: 2)
      end

      assert_equal 2, transfers.length
    end
  end

  context "#retrieve_1099_misc_capability" do
    test "returns a Stripe capability when 1099-MISC has been requested for the account" do
      stripe_account = create(:stripe_connect_account,
        stripe_account_id: "acct_1GuPRRIUvEAaxtx6")

      capability = VCR.use_cassette("stripe/retrieve_requested_capability") do
        stripe_account.retrieve_1099_misc_capability
      end

      refute_nil capability
      assert_instance_of Stripe::Capability, capability
      assert_predicate capability, :requested?
    end

    test "returns a Stripe capability when 1099-MISC has not been requested for the account" do
      stripe_account = create(:stripe_connect_account,
        stripe_account_id: "acct_1Gdg4SGfzt2kDZmO")

      capability = VCR.use_cassette("stripe/retrieve_capability") do
        stripe_account.retrieve_1099_misc_capability
      end

      refute_nil capability
      assert_instance_of Stripe::Capability, capability
      refute_predicate capability, :requested?
    end

    test "returns nil when the Stripe request fails" do
      stripe_account = create(:stripe_connect_account,
        stripe_account_id: "acct_1Gi4HFEmaMEzWuJu") # Canadian account

      capability = VCR.use_cassette("stripe/failed_retrieve_capability") do
        stripe_account.retrieve_1099_misc_capability
      end

      assert_nil capability
    end
  end

  context "#request_capability" do
    test "returns capability response for the specified capability" do
      stripe_account = create(:stripe_connect_account,
        stripe_account_id: "acct_1Gdg4SGfzt2kDZmO")

      response = VCR.use_cassette("stripe/request_capability") do
        stripe_account.request_capability("card_payments")
      end

      assert_predicate response, :success?
      capability = response.result
      assert_instance_of Stripe::Capability, capability
      assert_equal "card_payments", capability.id
      assert_predicate capability, :requested?
      assert_equal stripe_account.stripe_account_id, capability.account
    end

    test "handles error response from Stripe API" do
      stripe_account = create(:stripe_connect_account,
        stripe_account_id: "acct_1Gdg4SGfzt2kDZmO")

      response = VCR.use_cassette("stripe/failed_request_capability") do
        stripe_account.request_capability("not_even_a_real_capability")
      end

      refute_predicate response, :success?
      assert_instance_of Stripe::InvalidRequestError, response.error
      assert_equal "Unknown capability: not_even_a_real_capability.", response.error.message
    end
  end

  context "#retrieve_capability" do
    test "returns capability response for the specified capability" do
      stripe_account = create(:stripe_connect_account,
        stripe_account_id: "acct_1Gdg4SGfzt2kDZmO")
      capability_id = Billing::StripeConnect::Account::TAXES_1099_MISC_CAPABILITY

      response = VCR.use_cassette("stripe/retrieve_capability") do
        stripe_account.retrieve_capability(capability_id)
      end

      assert_predicate response, :success?
      capability = response.result
      assert_instance_of Stripe::Capability, capability
      assert_equal capability_id, capability.id
      assert_equal stripe_account.stripe_account_id, capability.account
      refute_predicate capability, :requested?
      assert_nil capability.requested_at
      assert_equal "unrequested", capability.status
      requirements = capability.requirements
      refute_nil requirements
      assert_nil requirements["current_deadline"]
      assert_nil requirements["disabled_reason"]
      assert_empty requirements["errors"]
      assert_empty requirements["past_due"]
      assert_empty requirements["pending_verification"]
      due_items = %w(company.address.city company.address.line1
        company.address.postal_code company.address.state)
      assert_same_elements due_items, requirements["currently_due"]
      assert_same_elements due_items, requirements["eventually_due"]
    end

    test "handles error responses from the Stripe API" do
      stripe_account = create(:stripe_connect_account,
        stripe_account_id: "acct_1Gi4HFEmaMEzWuJu") # Canadian account
      capability_id = Billing::StripeConnect::Account::TAXES_1099_MISC_CAPABILITY

      response = VCR.use_cassette("stripe/failed_retrieve_capability") do
        stripe_account.retrieve_capability(capability_id)
      end

      refute_predicate response, :success?
      assert_instance_of Stripe::InvalidRequestError, response.error
      assert_equal "The #{capability_id} capability is not requestable " \
        "for accounts in CA.", response.error.message
    end
  end

  context "#current_balance" do
    test "returns a balance response" do
      account_id = "acct_1Ep35IFxJZYbadPl"
      stripe_connect_account = create(:stripe_connect_account, stripe_account_id: account_id)

      response = VCR.use_cassette("stripe/retrieve_balance") do
        stripe_connect_account.current_balance
      end

      assert_predicate response, :success?
      balance_object = response.result
      assert_instance_of Stripe::Balance, balance_object
      available_balances = balance_object.available
      assert_equal 1, available_balances.size
      available_balance = available_balances.first
      assert_instance_of Stripe::StripeObject, available_balance
      assert_equal 16295, available_balance.amount
      assert_equal "usd", available_balance.currency
    end

    test "returns an error response when the Stripe request fails" do
      stripe_connect_account = create(:stripe_connect_account, stripe_account_id: "unavailable")

      response = VCR.use_cassette("stripe/retrieve_unavailable_balance") do
        stripe_connect_account.current_balance
      end

      refute_predicate response, :success?
      assert_instance_of Stripe::PermissionError, response.error
    end
  end

  context "#balance_available?" do
    test "returns true when balance is present" do
      stripe_connect_account = create(:stripe_connect_account, stripe_account_id: "acct_1Ep35IFxJZYbadPl")

      VCR.use_cassette("stripe/retrieve_balance") do
        assert_predicate stripe_connect_account, :balance_available?
      end
    end

    test "returns false when is not possible to fetch the current_balance" do
      VCR.use_cassette("stripe/retrieve_unavailable_balance") do
        stripe_connect_account = create(:stripe_connect_account, stripe_account_id: "unavailable")
        refute_predicate stripe_connect_account, :balance_available?
      end
    end
  end

  context "#balance_amount" do
    test "returns current balance amount" do
      stripe_connect_account = create(:stripe_connect_account, stripe_account_id: "acct_1Ep35IFxJZYbadPl")

      VCR.use_cassette("stripe/retrieve_balance") do
        assert_predicate stripe_connect_account, :balance_available?
      end

      assert_operator stripe_connect_account.balance_amount.amount, :>, 0
    end

    test "returns zero when the current balance is not available" do
      VCR.use_cassette("stripe/retrieve_unavailable_balance") do
        stripe_connect_account = create(:stripe_connect_account, stripe_account_id: "unavailable")
        assert_equal 0, stripe_connect_account.balance_amount.amount
      end
    end
  end

  context "#load_payout" do
    test "returns requested payout" do
      payout_id = "po_1JCwv52SjumVcZJ1Y5ZwuYEo"
      stripe_connect_account = create(:stripe_connect_account, stripe_account_id: "acct_1JCwpS2SjumVcZJ1")

      response = VCR.use_cassette("stripe/retrieve_payout") do
        stripe_connect_account.load_payout(payout_id)
      end

      assert_predicate response, :success?
      result = response.result
      assert_instance_of Billing::Stripe::Payout, result
      assert_equal 100_00, result.amount
      assert_equal 1626220800, result.arrival_date
      assert_equal 1626226191, result.created
      assert_equal "usd", result.currency
    end

    test "should override amount for huf currency" do
      stripe_connect_account = create(:stripe_connect_account, stripe_account_id: "acct_1MvkhMEEfpoHkWBU")
      payout_id = "po_1MvlJnEEfpoHkWBUPQ0vXq53"

      response = VCR.use_cassette("stripe/hungarian_payout") do
        stripe_connect_account.load_payout(payout_id)
      end

      assert_predicate response, :success?
      result = response.result
      assert_equal result.amount, 35400
    end
  end

  context "#stripe_payouts" do
    test "returns an array of billing stripe transfer records for the associated account_id" do
      account_id = "acct_1Ep35IFxJZYbadPl"
      stripe_connect_account = create(:stripe_connect_account, stripe_account_id: account_id)

      response = VCR.use_cassette("stripe/list_payouts") do
        stripe_connect_account.stripe_payouts
      end

      assert_predicate response, :success?
      assert_equal 2, response.result.length
    end

    test "allows passing in limit" do
      account_id = "acct_1Ep35IFxJZYbadPl"
      stripe_connect_account = create(:stripe_connect_account, stripe_account_id: account_id)

      response = VCR.use_cassette("stripe/list_payouts_with_limit") do
        stripe_connect_account.stripe_payouts(limit: 1)
      end

      assert_predicate response, :success?
      assert_equal 1, response.result.length
    end

    test "allows passing in status" do
      stripe_connect_account = create(:stripe_connect_account, stripe_account_id: "acct_1IF4dJ2Q42qEzmMv")

      response = VCR.use_cassette("stripe/list_paid_payouts") do
        stripe_connect_account.stripe_payouts(status: Billing::StripeConnect::Account::PayoutStatus::Paid)
      end

      assert_predicate response, :success?
      assert_equal 1, response.result.length
    end

    test "should override each amount for huf currency" do
      stripe_connect_account = create(:stripe_connect_account, stripe_account_id: "acct_1MvkhMEEfpoHkWBU")
      payout_id = "po_1MvmAbEEfpoHkWBUnXEXEwMo"

      response = VCR.use_cassette("stripe/hungarian_payout_list") do
        stripe_connect_account.stripe_payouts
      end

      assert_predicate response, :success?
      result = response.result
      assert_equal result.first.amount, 19031
      assert_equal result.second.amount, 35400
    end
  end

  context "#latest_payout_status_cache_key" do
    test "differs per Stripe account" do
      account1 = build(:stripe_connect_account, stripe_account_id: "abc123")
      account2 = build(:stripe_connect_account, stripe_account_id: "8675309")

      refute_nil account1.latest_payout_status_cache_key
      refute_nil account2.latest_payout_status_cache_key
      refute_equal account1.latest_payout_status_cache_key, account2.latest_payout_status_cache_key
    end
  end

  context "webhooks relation" do
    test "includes Stripe webhook for the account" do
      stripe_account = create(:stripe_connect_account, sponsors_listing: @user.sponsors_listing,
        stripe_account_id: "acct_1Ep35IFxJZYbadPl")
      other_stripe_account = create(:stripe_connect_account)

      webhook = create(:stripe_webhook, :payout_created)
      assert_equal stripe_account.stripe_account_id, webhook.account_id,
        "need webhook to be for the Stripe account"

      other_webhook = create(:stripe_webhook, kind: :payout_created, payload: {
        account: other_stripe_account.stripe_account_id
      })
      assert_equal other_stripe_account.stripe_account_id, other_webhook.account_id,
        "need other webhook to be for the other Stripe account"

      result = stripe_account.webhooks

      assert_includes result, webhook
      refute_includes result, other_webhook
    end
  end

  context "#latest_payout_status" do
    test "nil when there haven't been any payouts" do
      stripe_account = create(:stripe_connect_account, sponsors_listing: @user.sponsors_listing)
      # non-payout webhook to ensure its status isn't checked
      create(:stripe_webhook, :transfer_created, account: stripe_account.stripe_account_id)

      assert_nil stripe_account.latest_payout_status
    end

    test "nil when the Stripe request errors" do
      stripe_account = create(:stripe_connect_account, sponsors_listing: @user.sponsors_listing)
      create(:stripe_webhook, :payout_created,
        account: stripe_account.stripe_account_id,
        object: { id: "po_not_even_a_real_payout_id" })

      VCR.use_cassette("stripe/failed_retrieve_payout") do
        assert_nil stripe_account.latest_payout_status
      end
    end

    test "returns status of latest payout" do
      stripe_account = create(:stripe_connect_account, sponsors_listing: @user.sponsors_listing)
      create(:stripe_webhook, :payout_created,
        account: stripe_account.stripe_account_id,
        object: { id: "po_1JCwv52SjumVcZJ1Y5ZwuYEo" })

      VCR.use_cassette("stripe/retrieve_payout") do
        assert_equal "paid", stripe_account.latest_payout_status
      end
    end

    test "does not cache anything when there aren't payouts yet" do
      stripe_account = create(:stripe_connect_account, sponsors_listing: @user.sponsors_listing)
      assert_nil Billing::Kv.store.get(stripe_account.latest_payout_status_cache_key).value { nil }

      stripe_account.latest_payout_status

      assert_nil Billing::Kv.store.get(stripe_account.latest_payout_status_cache_key).value { nil }
    end

    test "caches the status from the Stripe API" do
      stripe_account = create(:stripe_connect_account, sponsors_listing: @user.sponsors_listing)
      create(:stripe_webhook, :payout_created,
        account: stripe_account.stripe_account_id,
        object: { id: "po_1JCwv52SjumVcZJ1Y5ZwuYEo" })
      assert_nil Billing::Kv.store.get(stripe_account.latest_payout_status_cache_key).value { nil }

      VCR.use_cassette("stripe/retrieve_payout") do
        # Prime the cache
        stripe_account.latest_payout_status
      end

      assert_equal "paid", Billing::Kv.store.get(stripe_account.latest_payout_status_cache_key).value { nil }
    end

    test "only makes one Stripe API request with repeated calls for the same account" do
      stripe_account1 = create(:stripe_connect_account, sponsors_listing: @user.sponsors_listing)
      stripe_account2 = create(:stripe_connect_account)
      webhook1 = create(:stripe_webhook, :payout_created,
        account: stripe_account1.stripe_account_id)
      webhook2 = create(:stripe_webhook, :payout_created,
        account: stripe_account2.stripe_account_id)

      payout1 = Stripe::Payout.construct_from(id: webhook1.stripe_object_id, status: "whee")
      Stripe::Payout.expects(:retrieve).once.
        with({
          id: webhook1.stripe_object_id,
          expand: ["destination"],
        }, stripe_account: stripe_account1.stripe_account_id).
        returns(payout1)
      payout2 = Stripe::Payout.construct_from(id: webhook2.stripe_object_id, status: "okay")
      Stripe::Payout.expects(:retrieve).once.
        with({
          id: webhook2.stripe_object_id,
          expand: ["destination"],
        }, stripe_account: stripe_account2.stripe_account_id).
        returns(payout2)

      stripe_account1.latest_payout_status
      stripe_account1.latest_payout_status
      stripe_account1.latest_payout_status

      stripe_account2.latest_payout_status
      stripe_account2.latest_payout_status
    end
  end

  context "#latest_payout_failed?" do
    test "true when payout failed" do
      failed_payout = stub(status: "failed")
      stripe_account = create(:stripe_connect_account, sponsors_listing: @user.sponsors_listing)
      create(:stripe_webhook, :payout_created, account: stripe_account.stripe_account_id)
      api_response = Billing::StripeConnect::Account::APIResult.success(
        account: stripe_account,
        result: failed_payout
      )
      Billing::StripeConnect::Account.any_instance.stubs(:latest_payout).returns(api_response)

      assert_predicate stripe_account, :latest_payout_failed?
    end

    test "false when there haven't been any payouts" do
      stripe_account = create(:stripe_connect_account, sponsors_listing: @user.sponsors_listing)
      # non-payout webhook to ensure its status isn't checked
      create(:stripe_webhook, :transfer_created, account: stripe_account.stripe_account_id)

      refute_predicate stripe_account, :latest_payout_failed?
    end

    test "false when the Stripe request errors" do
      stripe_account = create(:stripe_connect_account, sponsors_listing: @user.sponsors_listing)
      create(:stripe_webhook, :payout_created,
        account: stripe_account.stripe_account_id,
        object: { id: "po_not_even_a_real_payout_id" })

      VCR.use_cassette("stripe/failed_retrieve_payout") do
        refute_predicate stripe_account, :latest_payout_failed?
      end
    end

    test "false when latest payout succeeded" do
      stripe_account = create(:stripe_connect_account, sponsors_listing: @user.sponsors_listing)
      create(:stripe_webhook, :payout_created,
        account: stripe_account.stripe_account_id,
        object: { id: "po_1JCwv52SjumVcZJ1Y5ZwuYEo" })

      VCR.use_cassette("stripe/retrieve_payout") do
        refute_predicate stripe_account, :latest_payout_failed?
      end
    end
  end

  context "#latest_payout_created and #async_latest_payout_created" do
    test "returns the creation time of the latest payout" do
      stripe_account = create(:stripe_connect_account, sponsors_listing: @user.sponsors_listing)
      # see test/fixtures/billing/stripe/events/payout_created.json
      create(:stripe_webhook, :payout_created, account: stripe_account.stripe_account_id)
      expected = DateTime.new(2019, 7, 16, 19, 31, 23)

      assert_equal expected, stripe_account.latest_payout_created
      assert_equal expected, stripe_account.async_latest_payout_created.sync
    end

    test "returns nil when there hasn't been a payout" do
      stripe_account = create(:stripe_connect_account, sponsors_listing: @user.sponsors_listing)
      # non-payout webhook to ensure its creation date isn't returned
      create(:stripe_webhook, :transfer_created, account: stripe_account.stripe_account_id)

      assert_nil stripe_account.latest_payout_created
      assert_nil stripe_account.async_latest_payout_created.sync
    end
  end

  context "#latest_payout" do
    test "returns the latest payout" do
      stripe_account = create(:stripe_connect_account)
      Timecop.freeze(2.days.ago) do
        # old payout webhook
        create(:stripe_webhook, :payout_failed, account: stripe_account.stripe_account_id)
      end
      payout_id = "po_1JCwv52SjumVcZJ1Y5ZwuYEo"
      Timecop.freeze(1.day.ago) do
        # latest payout webhook
        create(:stripe_webhook, :payout_created,
          account: stripe_account.stripe_account_id,
          object: { id: payout_id })
      end

      response = VCR.use_cassette("stripe/retrieve_payout") do
        stripe_account.latest_payout
      end

      assert_instance_of Billing::StripeConnect::Account::APIResult, response
      assert_predicate response, :success?
      result = response.result
      assert_instance_of Billing::Stripe::Payout, result
      assert_equal result.id, payout_id
    end

    test "works for a payout in a connected account" do
      stripe_account = create(:stripe_connect_account,
        stripe_account_id: "acct_1Ep35IFxJZYbadPl")
      payout_id = "po_1HRhlDFxJZYbadPlQ2kWRHXt"
      create(:stripe_webhook, :payout_created,
        account: stripe_account.stripe_account_id,
        object: { id: payout_id })

      response = VCR.use_cassette("stripe/retrieve_connected_account_payout") do
        stripe_account.latest_payout
      end

      assert_instance_of Billing::StripeConnect::Account::APIResult, response
      assert_predicate response, :success?
      result = response.result
      assert_instance_of Billing::Stripe::Payout, result
      assert_equal result.id, payout_id
    end
  end

  context "Hydro instrumentation" do
    test "emits Hydro event on create for a Sponsors Stripe account" do
      listing = @user.sponsors_listing

      assert_hydro_messages(count: 0, schema: "github.sponsors.v1.StripeConnectAccountCreate")

      stripe_account = create(:stripe_connect_account, sponsors_listing: listing)

      assert_hydro_messages(count: 1, schema: "github.sponsors.v1.StripeConnectAccountCreate")
      assert_hydro_published({
        request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
        sponsors_listing: Hydro::EntitySerializer.sponsors_listing(listing),
        sponsorable: Hydro::EntitySerializer.user(@user),
        stripe_connect_account: Hydro::EntitySerializer.stripe_connect_account(stripe_account),
        sponsors_listing_stafftools_metadata: Hydro::EntitySerializer
          .sponsors_listing_stafftools_metadata(listing.stafftools_metadata),
      }, schema: "github.sponsors.v1.StripeConnectAccountCreate")
    end

    test "emits Hydro event on update for a Sponsors Stripe account" do
      listing = @user.sponsors_listing
      stripe_account = create(:stripe_connect_account, sponsors_listing: listing, email: "oldEmail@example.com")
      new_email = "newEmail@example.com"

      assert_hydro_messages(count: 0, schema: "github.sponsors.v1.StripeConnectAccountUpdate")

      stripe_account.update!(email: new_email)

      assert_hydro_messages(count: 1, schema: "github.sponsors.v1.StripeConnectAccountUpdate")
      assert_hydro_published({
        request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
        sponsors_listing: Hydro::EntitySerializer.sponsors_listing(listing),
        sponsorable: Hydro::EntitySerializer.user(@user),
        stripe_connect_account: Hydro::EntitySerializer.stripe_connect_account(stripe_account),
        sponsors_listing_stafftools_metadata: Hydro::EntitySerializer
          .sponsors_listing_stafftools_metadata(listing.stafftools_metadata),
      }, schema: "github.sponsors.v1.StripeConnectAccountUpdate")
    end

    test "emits Hydro event on delete for a Sponsors Stripe account" do
      listing = @user.sponsors_listing
      stripe_account = create(:stripe_connect_account, sponsors_listing: listing)
      expected_payload = {
        request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
        sponsors_listing: Hydro::EntitySerializer.sponsors_listing(listing),
        sponsorable: Hydro::EntitySerializer.user(@user),
        stripe_connect_account: Hydro::EntitySerializer.stripe_connect_account(stripe_account),
        sponsors_listing_stafftools_metadata: Hydro::EntitySerializer
          .sponsors_listing_stafftools_metadata(listing.stafftools_metadata),
      }

      assert_hydro_messages(count: 0, schema: "github.sponsors.v1.StripeConnectAccountDelete")

      stripe_account.destroy!

      assert_hydro_messages(count: 1, schema: "github.sponsors.v1.StripeConnectAccountDelete")
      assert_hydro_published(expected_payload, schema: "github.sponsors.v1.StripeConnectAccountDelete")
    end
  end

  context "#create_payout" do
    test "returns payout response" do
      stripe_account = create(:stripe_connect_account, stripe_account_id: "acct_1Ep35IFxJZYbadPl")

      response = VCR.use_cassette("stripe/issue_manual_payout") do
        stripe_account.create_payout!
      end

      assert_instance_of Billing::StripeConnect::Account::APIResult, response
      assert_predicate response, :success?
      assert_equal 1, response.result.length

      payout = response.result.first
      assert_instance_of Stripe::Payout, payout
      assert_equal "po_1Iy01GFxJZYbadPlwbV8e129", payout.id
    end

    test "instruments audit log event for create payouts" do
      stripe_account = create(:stripe_connect_account, stripe_account_id: "acct_1Ep35IFxJZYbadPl")
      listing = stripe_account.sponsors_listing
      sponsorable = listing.sponsorable
      staff = create(:staff_admin_user)

      events = subscribe "sponsors_listing.issue_manual_payout"

      VCR.use_cassette("stripe/issue_manual_payout") do
        stripe_account.create_payout!(actor: staff, reason: "Issue payouts")
      end

      expected_payload = GitHub.guarded_audit_log_staff_actor_entry(staff).merge(
        user: sponsorable.login,
        user_id: sponsorable.id,
        sponsors_listing_id: listing.id,
        short_description: listing.short_description,
        sponsors_listing: listing.slug,
        state: :draft,
        created_by: listing.created_by.login,
        created_by_id: listing.created_by_id,
        reason: "Issue payouts",
        stripe_connect_account: "acct_1Ep35IFxJZYbadPl",
        stripe_connect_account_id: stripe_account.id,
      )

      assert event = events.pop, "an event was expected"
      assert_equal expected_payload, event.payload
    end

    test "instruments hydro event for issue payouts" do
      stripe_account = create(:stripe_connect_account, stripe_account_id: "acct_1Ep35IFxJZYbadPl")
      listing = stripe_account.sponsors_listing
      metadata = listing.stafftools_metadata
      staff = create(:staff_admin_user)

      VCR.use_cassette("stripe/issue_manual_payout") do
        stripe_account.create_payout!(actor: staff, reason: "Issue payouts")
      end

      expected_hydro_payload = {
        request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
        listing: Hydro::EntitySerializer.sponsors_listing(listing),
        actor: Hydro::EntitySerializer.user(staff),
        reason: "Issue payouts",
        stripe_account_id: stripe_account.stripe_account_id,
        sponsorable: Hydro::EntitySerializer.user(listing.sponsorable),
        stripe_connect_account: Hydro::EntitySerializer.stripe_connect_account(stripe_account),
        listing_stafftools_metadata: Hydro::EntitySerializer.sponsors_listing_stafftools_metadata(metadata),
      }

      assert_hydro_published(expected_hydro_payload, schema: "github.sponsors.v1.IssueManualPayout")
    end
  end

  context "#disable_payouts" do
    test "calls ConfigureStripeAccountJob with freeze_payouts: true" do
      Stripe::Account.stubs(:update).returns(true)

      account = create(:stripe_connect_account)
      ConfigureStripeAccountJob.expects(:perform_later)
        .once
        .with(account, freeze_payouts: true, actor: nil, reason: nil)

      account.disable_payouts
    end
  end

  context "#disable_payouts!" do
    test "returns updated account when disabling payouts" do
      account = create(:stripe_connect_account)
      response = Stripe::Account.construct_from(
        id: account.stripe_account_id,
        settings: {
          payouts: {
            schedule: {
              delay_days: 2,
              interval: "manual",
            },
          },
        },
      )
      Stripe::Account.stubs(:update).returns(response)

      result = account.disable_payouts!
      assert_equal result, account.reload
      assert_equal "manual", account.payout_interval
    end
  end

  context "#enable_payouts" do
    test "calls ConfigureStripeAccountJob with freeze_payouts: false" do
      Stripe::Account.stubs(:update).returns(true)

      account = create(:stripe_connect_account)
      ConfigureStripeAccountJob.expects(:perform_later)
        .once
        .with(account, freeze_payouts: false, actor: nil)

      account.enable_payouts
    end
  end

  context "#enable_payouts!" do
    test "returns updated account when enabling payouts" do
      account = create(:stripe_connect_account)
      response = Stripe::Account.construct_from(
        id: account.stripe_account_id,
        settings: {
          payouts: {
            debit_negative_balances: true,
            schedule: {
              delay_days: 2,
              interval: "monthly",
              monthly_anchor: 22,
            },
            statement_descriptor: nil,
          },
        },
      )
      Stripe::Account.stubs(:update).returns(response)

      result = account.enable_payouts!
      assert_equal result, account.reload
      assert_equal "monthly", account.payout_interval
    end
  end

  context "#soft_delete" do
    test "emits a Hydro event and sets deleted_at" do
      travel_to "2023-11-13"
      listing = @user.sponsors_listing
      stripe_account = create(:stripe_connect_account, sponsors_listing: listing, deleted_at: nil)

      stripe_account.soft_delete

      refute_nil stripe_account.reload.deleted_at
      assert_hydro_messages(count: 1, schema: "github.sponsors.v1.StripeConnectAccountUpdate")
      assert_hydro_published({
        request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
        sponsors_listing: Hydro::EntitySerializer.sponsors_listing(listing),
        sponsorable: Hydro::EntitySerializer.user(@user),
        stripe_connect_account: Hydro::EntitySerializer.stripe_connect_account(stripe_account),
        sponsors_listing_stafftools_metadata: Hydro::EntitySerializer
          .sponsors_listing_stafftools_metadata(listing.stafftools_metadata),
      }, schema: "github.sponsors.v1.StripeConnectAccountUpdate")
    end
  end

  context "#stripe_onboarding_url!" do
    test "calls the Stripe API to generate an onboarding link" do
      listing = create(:sponsors_listing, :with_stripe_account)
      sponsorable = listing.sponsorable
      account = listing.active_stripe_connect_account

      api_response_stub = stub(url: "https://stripe.com")

      ::Stripe::AccountLink.expects(:create).with(
        account: account.stripe_account_id,
        refresh_url: "http://#{GitHub.host_name}/sponsors/#{sponsorable}/stripe_accounts/#{account}",
        return_url: "http://#{GitHub.host_name}/sponsors/#{sponsorable}/stripe_accounts/#{account}/edit",
        type: :account_onboarding,
      ).returns(api_response_stub)

      onboarding_url = account.stripe_onboarding_url!(
        refresh_url: UrlHelpers.sponsorable_stripe_account_url(
          sponsorable,
          account,
          host: GitHub.host_name,
        ),
        return_url: UrlHelpers.edit_sponsorable_stripe_account_url(
          sponsorable,
          account,
          host: GitHub.host_name,
        ),
      )

      assert_equal api_response_stub.url, onboarding_url
    end
  end

  context "#synced?" do
    test "returns true if the account has an email" do
      account = build(:stripe_connect_account, email: "test@github.com")
      assert_predicate account, :synced?
    end

    test "returns false if the account doesn't have an email" do
      account = build(:stripe_connect_account, email: nil)
      refute_predicate account, :synced?
    end
  end

  context ".currency_threshold" do
    test "returns payout threshhold in cents of the associated currency" do
      assert_equal 100, Billing::StripeConnect::Account.payout_threshold_for(:gbp)
    end

    test "returns 0 if the currency has no payout threshold" do
      assert_equal 0, Billing::StripeConnect::Account.payout_threshold_for(:usd)
    end
  end

  test "ensure all country codes match intended countries" do
    regions = Billing::StripeConnect::Account::supported_countries.map do |code|
      Billing::StripeConnect::Account.country_name_for(code)
    end

    expected_regions = [
      "Albania", "Antigua and Barbuda", "Argentina", "Armenia", "Australia", "Austria", "Bahrain", "Belgium",
      "Bolivia", "Bosnia and Herzegovina", "Brazil", "Bulgaria", "Cambodia", "Canada", "Chile", "Colombia",
      "Costa Rica", "Côte d'Ivoire", "Croatia", "Cyprus", "Czech Republic", "Denmark", "Dominican Republic",
      "Ecuador", "Egypt", "El Salvador", "Estonia", "Ethiopia", "Finland", "France", "Gambia", "Germany", "Ghana",
      "Gibraltar", "Greece", "Guatemala", "Guyana", "Hong Kong", "Hungary", "Iceland", "India", "Indonesia",
      "Ireland", "Israel", "Italy", "Jamaica", "Japan", "Jordan", "Kenya", "Kuwait", "Latvia", "Liechtenstein",
      "Lithuania", "Luxembourg", "Macau", "Madagascar", "Malaysia", "Malta", "Mauritius", "Mexico", "Moldova",
      "Mongolia", "Morocco", "Namibia", "Netherlands", "New Zealand", "Nigeria", "Macedonia", "Norway",
      "Oman", "Panama", "Paraguay", "Peru", "Philippines", "Poland", "Portugal", "Qatar", "Romania", "Rwanda",
      "Saudi Arabia", "Senegal", "Serbia", "Singapore", "Slovakia", "Slovenia", "South Africa", "Korea, South",
      "Spain", "Sri Lanka", "Saint Lucia", "Sweden", "Switzerland", "Tanzania", "Thailand", "Trinidad and Tobago",
      "Tunisia", "Türkiye", "United Arab Emirates", "United Kingdom", "United States of America", "Uruguay",
      "Uzbekistan", "Vietnam"
    ]

    assert_same_elements expected_regions, regions
  end
end
