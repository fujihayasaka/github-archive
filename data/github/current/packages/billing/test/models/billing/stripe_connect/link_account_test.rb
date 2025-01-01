# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::StripeConnect::LinkAccountTest < GitHub::BillingTestCase
  fixtures do
    @staff = create(:staff_admin_user)
    @sponsors_listing = create(:sponsors_listing, billing_country: "ES", country_of_residence: "GB")

    @original_details1 = {
      default_currency: "usd",
      payout_interval: "monthly",
      billing_country: "US",
      country: "US",
      charges_enabled: true,
      payouts_enabled: true,
      email: Sham.email,
      card_payments_capability: true,
      tax_reporting_capability: true,
      transfers_capability: true,
      details_submitted: true,
      requirements_currently_due: false,
      requirements_eventually_due: false,
      requirements_past_due: false,
      current_requirements_deadline: nil,
      disabled_reason: nil,
    }
    @stripe_account1 = create(:stripe_connect_account, active: true, sponsors_listing: @sponsors_listing, **@original_details1)
  end

  setup do
    @original_details2 = {
      default_currency: "usd",
      payout_interval: "manual",
      billing_country: "CA",
      country: "MX",
      charges_enabled: false,
      payouts_enabled: false,
      email: Sham.email,
      disabled_reason: "requirements.past_due",
      card_payments_capability: true,
      tax_reporting_capability: false,
      transfers_capability: true,
      details_submitted: true,
      requirements_currently_due: true,
      requirements_eventually_due: false,
      requirements_past_due: true,
      current_requirements_deadline: 1.month.from_now.freeze,
    }
    @stripe_account2 = create(:stripe_connect_account, active: false, sponsors_listing: @sponsors_listing,
      **@original_details2)
  end

  context ".call" do
    test "creates a new active Stripe account for the specified Sponsors listing and loads details from Stripe API" do
      stripe_account_id = "acct_1Ixxfd2RynYkVPBu"
      sponsors_listing = create(:sponsors_listing, billing_country: "ES", country_of_residence: "GB")

      new_stripe_account = VCR.use_cassette("stripe/fetch_account_details") do
        assert_difference -> { Billing::StripeConnect::Account.count } do
          Billing::StripeConnect::LinkAccount.call(stripe_account_id: stripe_account_id,
            sponsors_listing: sponsors_listing, actor: @staff)
        end
      end

      refute_nil new_stripe_account
      assert_equal stripe_account_id, new_stripe_account.stripe_account_id
      assert_equal new_stripe_account, sponsors_listing.reload_active_stripe_connect_account
      assert_predicate new_stripe_account, :active?
      assert_equal "stripe-manual-payout-test@gmail.com", new_stripe_account.email
      assert_equal "usd", new_stripe_account.default_currency
      assert_equal "US", new_stripe_account.billing_country
      assert_equal "US", new_stripe_account.country
      assert_equal "US", sponsors_listing.reload.billing_country,
        "should have updated Sponsors listing with active Stripe account's details"
      assert_equal "US", sponsors_listing.country_of_residence,
        "should have updated Sponsors listing with active Stripe account's details"
      assert_nil new_stripe_account.disabled_reason
      assert_nil new_stripe_account.current_requirements_deadline
      refute_predicate new_stripe_account, :requirements_currently_due?
      refute_predicate new_stripe_account, :requirements_eventually_due?
      refute_predicate new_stripe_account, :requirements_past_due?
      refute_predicate new_stripe_account, :card_payments_capability?
      assert_predicate new_stripe_account, :verified_verification_status?
      assert_predicate new_stripe_account, :payouts_enabled?
      assert_predicate new_stripe_account, :charges_enabled?
      assert_predicate new_stripe_account, :tax_reporting_capability?
      assert_predicate new_stripe_account, :transfers_capability?
      assert_predicate new_stripe_account, :details_submitted?
      assert_equal "monthly", new_stripe_account.payout_interval
    end

    test "creates a new inactive Stripe account for the specified Sponsors listing and loads details from Stripe API" do
      stripe_account_id = "acct_1Ixxfd2RynYkVPBu"

      new_stripe_account = VCR.use_cassette("stripe/fetch_account_details") do
        assert_difference -> { Billing::StripeConnect::Account.count } do
          Billing::StripeConnect::LinkAccount.call(stripe_account_id: stripe_account_id,
            sponsors_listing: @sponsors_listing, actor: @staff)
        end
      end

      refute_nil new_stripe_account
      assert_equal stripe_account_id, new_stripe_account.stripe_account_id
      assert_equal @stripe_account1, @sponsors_listing.reload_active_stripe_connect_account,
        "should not have changed which Stripe account was active for the Sponsors listing"
      assert_equal "ES", @sponsors_listing.reload.billing_country,
        "should not have changed listing's details for new inactive Stripe account"
      assert_equal "GB", @sponsors_listing.country_of_residence,
        "should not have changed listing's details for new inactive Stripe account"
      assert_equal @sponsors_listing, new_stripe_account.sponsors_listing
      refute_predicate new_stripe_account, :active?
      assert_equal "stripe-manual-payout-test@gmail.com", new_stripe_account.email
      assert_equal "usd", new_stripe_account.default_currency
      assert_equal "US", new_stripe_account.billing_country
      assert_equal "US", new_stripe_account.country
      assert_nil new_stripe_account.disabled_reason
      assert_nil new_stripe_account.current_requirements_deadline
      refute_predicate new_stripe_account, :requirements_currently_due?
      refute_predicate new_stripe_account, :requirements_eventually_due?
      refute_predicate new_stripe_account, :requirements_past_due?
      refute_predicate new_stripe_account, :card_payments_capability?
      assert_predicate new_stripe_account, :verified_verification_status?
      assert_predicate new_stripe_account, :payouts_enabled?
      assert_predicate new_stripe_account, :charges_enabled?
      assert_predicate new_stripe_account, :tax_reporting_capability?
      assert_predicate new_stripe_account, :transfers_capability?
      assert_predicate new_stripe_account, :details_submitted?
      assert_equal "monthly", new_stripe_account.payout_interval
    end

    test "creates an audit log event" do
      stripe_account_id = "acct_1Ixxfd2RynYkVPBu"
      expected_payload = {
        active: false,
        verified: true,
        payouts_enabled: true,
        details_submitted: true,
        charges_enabled: true,
        requirements_past_due: false,
        current_requirements_deadline: nil,
        tax_reporting_capability: true,
        card_payments_capability: false,
        transfers_capability: true,
        requirements_currently_due: false,
        requirements_eventually_due: false,
        stripe_connect_account: stripe_account_id,
        sponsors_listing_id: @sponsors_listing.id,
        sponsors_listing: @sponsors_listing.slug,
        country: "US",
        billing_country: "US",
        user: @sponsors_listing.sponsorable_login,
        user_id: @sponsors_listing.sponsorable_id,
        email: "stripe-manual-payout-test@gmail.com",
        default_currency: "usd",
        disabled_reason: nil,
        payout_interval: "monthly",
      }.merge(GitHub.guarded_audit_log_staff_actor_entry(@staff))
      events = subscribe("stripe_connect_account.link_account")

      new_stripe_account = VCR.use_cassette("stripe/fetch_account_details") do
        assert_difference -> { Billing::StripeConnect::Account.count } do
          Billing::StripeConnect::LinkAccount.call(stripe_account_id: stripe_account_id,
            sponsors_listing: @sponsors_listing, actor: @staff)
        end
      end

      refute_nil event = events.pop, "an event was expected"
      expected_payload[:stripe_connect_account_id] = new_stripe_account.id
      assert_equal expected_payload.sort, event.payload.sort
    end

    test "does not allow linking an existing Stripe account to a different Sponsors listing, even when account's Sponsors listing is invalid" do
      stripe_account = create(:stripe_connect_account, stripe_account_id: "acct_1Ixxfd2RynYkVPBu")
      stripe_account.sponsors_listing.delete
      refute_nil stripe_account.reload.sponsors_listing_id
      assert_nil stripe_account.sponsors_listing

      error = assert_no_difference(-> { Billing::StripeConnect::Account.count }) do
        assert_raises(Billing::StripeConnect::LinkAccount::ValidationError) do
          VCR.use_cassette("stripe/fetch_account_details") do
            Billing::StripeConnect::LinkAccount.call(
              stripe_account_id: stripe_account.stripe_account_id,
              sponsors_listing: @sponsors_listing,
              actor: @staff,
            )
          end
        end
      end

      assert_equal "Could not save Stripe account: Failed to update account from Stripe: Stripe account has " \
        "already been taken", error.message
    end

    test "no-op for existing Sponsors listing and active Stripe account link" do
      result = assert_no_difference -> { Billing::StripeConnect::Account.count } do
        Billing::StripeConnect::LinkAccount.call(
          stripe_account_id: @stripe_account1.stripe_account_id,
          sponsors_listing: @sponsors_listing,
          actor: @staff,
        )
      end

      assert_equal @stripe_account1.reload, result
      assert_equal @stripe_account1, @sponsors_listing.reload_active_stripe_connect_account
      @original_details1.each do |key, value|
        assert_stripe_account_value_unchanged value, @stripe_account1[key], key
      end
    end

    test "no-op for existing Sponsors listing and inactive Stripe account link" do
      result = assert_no_difference -> { Billing::StripeConnect::Account.count } do
        Billing::StripeConnect::LinkAccount.call(
          stripe_account_id: @stripe_account2.stripe_account_id,
          sponsors_listing: @sponsors_listing,
          actor: @staff,
        )
      end

      assert_equal @stripe_account2.reload, result
      refute_predicate @stripe_account2, :active?
      assert_equal @sponsors_listing, @stripe_account2.sponsors_listing
      @original_details2.each do |key, value|
        assert_stripe_account_value_unchanged value, @stripe_account2[key], key
      end
    end

    test "raises error when trying to associate an existing Stripe account with a different Sponsors listing" do
      other_listing = create(:sponsors_listing)
      error = assert_raises(Billing::StripeConnect::LinkAccount::ValidationError) do
        Billing::StripeConnect::LinkAccount.call(
          sponsors_listing: other_listing,
          stripe_account_id: @stripe_account1.stripe_account_id,
          actor: @staff,
        )
      end
      assert_equal "Stripe account #{@stripe_account1.stripe_account_id} is already tied to #{@sponsors_listing}",
        error.message
      assert_equal @sponsors_listing, @stripe_account1.reload.sponsors_listing
    end

    test "raises error when invalid Stripe account ID is given" do
      error = assert_no_difference(-> { Billing::StripeConnect::Account.count }) do
        assert_raises(Billing::StripeConnect::LinkAccount::StripeSyncError) do
          VCR.use_cassette("stripe/fetch_bad_account_details") do
            Billing::StripeConnect::LinkAccount.call(
              sponsors_listing: @sponsors_listing,
              stripe_account_id: "acct_1FZSIRIf4ogEXaVr",
              actor: @staff,
            )
          end
        end
      end
      assert_match /Could not sync account details with Stripe/, error.message
      assert_match /does not have access to account/, error.message
      assert_match /that account does not exist/, error.message
    end

    test "raises error when Stripe account does not save" do
      Billing::StripeConnect::Account.any_instance.stubs(:save).returns(false)
      Billing::StripeConnect::Account.any_instance.stubs(:errors).returns(stub(full_messages: ["o noes"]))

      error = assert_raises(Billing::StripeConnect::LinkAccount::ValidationError) do
        VCR.use_cassette("stripe/fetch_account_details") do
          Billing::StripeConnect::LinkAccount.call(
            stripe_account_id: "acct_1Ixxfd2RynYkVPBu",
            sponsors_listing: @sponsors_listing,
            actor: @staff,
          )
        end
      end
      assert_equal "Could not save Stripe account: Failed to update account from Stripe: o noes", error.message
    end

    test "raises error when nil Stripe account ID is given" do
      error = assert_raises(Billing::StripeConnect::LinkAccount::ValidationError) do
        Billing::StripeConnect::LinkAccount.call(sponsors_listing: @sponsors_listing, stripe_account_id: nil, actor: @staff)
      end
      assert_equal "Stripe account ID is required", error.message
    end

    test "raises error when nil Sponsors listing is given" do
      error = assert_raises(Billing::StripeConnect::LinkAccount::ValidationError) do
        Billing::StripeConnect::LinkAccount.call(sponsors_listing: nil, stripe_account_id: "abc123", actor: @staff)
      end
      assert_equal "Sponsors listing to associate with the Stripe account is required", error.message
    end

    test "raises error when nil actor is given" do
      error = assert_raises(Billing::StripeConnect::LinkAccount::ValidationError) do
        Billing::StripeConnect::LinkAccount.call(sponsors_listing: @sponsors_listing, stripe_account_id: "abc123", actor: nil)
      end
      assert_equal "Actor is required", error.message
    end

    test "raises error when blank Stripe account ID is given" do
      error = assert_raises(Billing::StripeConnect::LinkAccount::ValidationError) do
        Billing::StripeConnect::LinkAccount.call(sponsors_listing: @sponsors_listing, stripe_account_id: "", actor: @staff)
      end
      assert_equal "Stripe account ID is required", error.message
    end
  end

  def assert_stripe_account_value_unchanged(original_value, current_value, field)
    error_message = "#{field} should not have changed"
    if original_value.nil?
      assert_nil current_value, error_message
    elsif original_value.is_a?(Time)
      assert_equal original_value.to_s, current_value.to_s, error_message
    else
      assert_equal original_value, current_value, error_message
    end
  end
end
