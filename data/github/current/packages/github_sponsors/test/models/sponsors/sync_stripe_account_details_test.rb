# typed: true
# frozen_string_literal: true

require "test_helper"

class Sponsors::SyncStripeAccountDetailsTest < GitHub::TestCase
  include DogstatsTestHelpers
  include HydroTestHelpers

  fixtures do
    @account = create(:stripe_connect_account, :unverified, :charges_disabled,
      :payouts_disabled, country: nil, billing_country: nil)
    @sponsors_listing = @account.sponsors_listing
  end

  setup do
    skip unless GitHub.sponsors_enabled?
    @details_hash = {
      "id" => @account.stripe_account_id,
      "object" => "account",
      "charges_enabled" => true,
      "payouts_enabled" => true,
      "country" => "US",
      "external_accounts" => { "data" => [{ "country" => "CA" }] },
      "individual" => { "verification" => { "status" => "verified" } },
      "requirements" => { "eventually_due" => [] },
      "details_submitted" => true,
      "capabilities" => {
        "transfers" => "active",
        "card_payments" => "active",
        "tax_reporting_us_1099_misc" => "active"
      },
    }
    @details_response = Stripe::Account.construct_from(@details_hash)
  end

  context ".call" do
    test "updates verified status and fields that factor into it" do
      account = create(:stripe_connect_account, :unverified, stripe_account_id: "acct_1Ixxfd2RynYkVPBu",
        transfers_capability: false, tax_reporting_capability: false, card_payments_capability: true,
        details_submitted: false, billing_country: "CA")

      account = VCR.use_cassette("stripe/fetch_account_details") do
        Sponsors::SyncStripeAccountDetails.call(account)
      end

      assert_instance_of Billing::StripeConnect::Account, account
      assert_predicate account, :verified_verification_status?
      assert_predicate account, :transfers_capability?, "should have marked transfers_capability=true " \
        "when API returned platform_payments capability as active"
      assert_predicate account, :tax_reporting_capability?
      refute_predicate account, :card_payments_capability?
      assert_predicate account, :details_submitted?
      assert_equal "US", account.billing_country
    end

    test "emits a Hydro event" do
      Stripe::Account.stubs(:retrieve).returns(@details_response)

      Sponsors::SyncStripeAccountDetails.call(@account)

      assert_hydro_messages(count: 1, schema: "github.sponsors.v1.StripeConnectAccountUpdate")
      assert_hydro_published({
        request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
        sponsors_listing: Hydro::EntitySerializer.sponsors_listing(@sponsors_listing.reload),
        sponsorable: Hydro::EntitySerializer.user(@sponsors_listing.sponsorable),
        stripe_connect_account: Hydro::EntitySerializer.stripe_connect_account(@account),
        sponsors_listing_stafftools_metadata: Hydro::EntitySerializer
          .sponsors_listing_stafftools_metadata(@sponsors_listing.stafftools_metadata),
      }, schema: "github.sponsors.v1.StripeConnectAccountUpdate")
    end

    test "increments count in DataDog when account is successfully updated" do
      Stripe::Account.stubs(:retrieve).returns(@details_response)

      assert_difference(-> { GitHub.dogstats.increments("stripe.account_sync").size }) do
        assert_no_difference(-> { GitHub.dogstats.increments("stripe.account_sync_error").size }) do
          Sponsors::SyncStripeAccountDetails.call(@account)
        end
      end

      expected_datadog_tags = ["payable_type:SponsorsListing", "active:true", "has_email:false",
        "verification_status:verified"]
      assert_equal 1, GitHub.dogstats.increments("stripe.account_sync")
        .count { |x| x.tags.to_a == expected_datadog_tags }
    end

    test "marks our account as deleted when account doesn't exist on Stripe" do
      @account.update_attribute(:stripe_account_id, "acct_1FZSIRIf4ogEXaVr") # see fetch_bad_account_details cassette
      assert_nil @account.deleted_at

      assert_difference(-> { GitHub.dogstats.increments("stripe.account_sync").size }) do
        assert_no_difference(-> { GitHub.dogstats.increments("stripe.account_sync_error").size }) do
          VCR.use_cassette("stripe/fetch_bad_account_details") do
            Sponsors::SyncStripeAccountDetails.call(@account)
          end
        end
      end

      refute_nil @account.reload.deleted_at
      expected_datadog_tags = ["payable_type:SponsorsListing", "active:true", "has_email:true",
        "verification_status:unverified"]
      assert_equal 1, GitHub.dogstats.increments("stripe.account_sync")
        .count { |x| x.tags.to_a == expected_datadog_tags }
    end

    test "increments count in DataDog when Stripe error occurs" do
      Stripe::Account.expects(:retrieve).once.with(@account.stripe_account_id).raises(Stripe::StripeError)

      assert_no_difference(-> { GitHub.dogstats.increments("stripe.account_sync").size }) do
        assert_difference(-> { GitHub.dogstats.increments("stripe.account_sync_error").size }) do
          assert_raises(Stripe::StripeError) do
            Sponsors::SyncStripeAccountDetails.call(@account)
          end
        end
      end

      expected_datadog_tags = ["payable_type:SponsorsListing", "active:true", "has_email:true",
        "verification_status:unverified"]
      assert_equal 1, GitHub.dogstats.increments("stripe.account_sync_error")
        .count { |x| x.tags.to_a == expected_datadog_tags }
    end

    # See https://github.com/github/sponsors/issues/2661#issuecomment-878425839
    test "respects platform_payments as equivalent to transfers capability" do
      refute_predicate @account, :verified_verification_status?
      refute_predicate @account, :transfers_capability?
      Stripe::Account.stubs(:retrieve).returns(@details_response)

      Sponsors::SyncStripeAccountDetails.call(@account)

      assert_predicate @account.reload, :verified_verification_status?
      assert_predicate @account, :transfers_capability?
    end

    # See https://github.com/github/sponsors/issues/2661#issuecomment-885006960
    test "respects beneficiary_transfers as equivalent to transfers capability" do
      refute_predicate @account, :verified_verification_status?
      refute_predicate @account, :transfers_capability?
      Stripe::Account.stubs(:retrieve).returns(@details_response)

      Sponsors::SyncStripeAccountDetails.call(@account)

      assert_predicate @account.reload, :verified_verification_status?
      assert_predicate @account, :transfers_capability?
    end

    test "updates Stripe account details" do
      Stripe::Account.stubs(:retrieve).returns(@details_response)

      refute_predicate @account, :verified_verification_status?
      refute_predicate @account, :charges_enabled?
      refute_predicate @account, :payouts_enabled?
      assert_nil @account.country
      assert_nil @account.billing_country

      Sponsors::SyncStripeAccountDetails.call(@account)

      assert_predicate @account.reload, :verified_verification_status?
      assert_predicate @account, :charges_enabled?
      assert_predicate @account, :payouts_enabled?
      assert_equal "US", @account.country
      assert_equal "CA", @account.billing_country
    end

    test "updates billing_country on Sponsors listing when Stripe account is active" do
      Stripe::Account.stubs(:retrieve).returns(@details_response)
      @sponsors_listing.update_attribute(:billing_country, nil)
      assert_predicate @account, :active?

      Sponsors::SyncStripeAccountDetails.call(@account)

      assert_equal "CA", @sponsors_listing.reload.billing_country
    end

    test "does not update billing_country on Sponsors listing when Stripe account is inactive" do
      Stripe::Account.stubs(:retrieve).returns(@details_response)
      @sponsors_listing.update_attribute(:billing_country, nil)
      @account.update!(active: false)

      Sponsors::SyncStripeAccountDetails.call(@account)

      assert_nil @sponsors_listing.reload.billing_country
    end

    test "does not require tax_reporting_us_1099_misc capability for verification with a non-US account" do
      refute_predicate @account, :verified_verification_status?
      refute_predicate @account, :tax_reporting_capability?
      Stripe::Account.stubs(:retrieve).returns(Stripe::Account.construct_from(@details_hash.merge(
        "country" => "CA",
        "capabilities" => { "transfers" => "active" },
      )))

      Sponsors::SyncStripeAccountDetails.call(@account)

      assert_predicate @account.reload, :verified_verification_status?
      refute_predicate @account, :tax_reporting_capability?
    end

    test "requires tax_reporting_us_1099_misc capability for verification with US bank account" do
      refute_predicate @account, :verified_verification_status?
      refute_predicate @account, :tax_reporting_capability?
      Stripe::Account.stubs(:retrieve).returns(Stripe::Account.construct_from(@details_hash.merge(
        "external_accounts" => { "data" => [{ "country" => "US" }] },
        "capabilities" => { "transfers" => "active" },
      )))
      Sponsors::SyncStripeAccountDetails.call(@account)

      refute_predicate @account.reload, :verified_verification_status?
      refute_predicate @account, :tax_reporting_capability?
    end

    test "does not require tax_reporting_us_1099_misc capability for verification with US bank account for fiscally hosted listing" do
      child_listing = create(:sponsors_listing, :with_fiscal_host, :for_org)
      account = create(:stripe_connect_account, :unverified, sponsors_listing: child_listing, tax_reporting_capability: false)
      Stripe::Account.stubs(:retrieve).returns(Stripe::Account.construct_from(@details_hash.merge(
        "id" => account.stripe_account_id,
        "external_accounts" => { "data" => [{ "country" => "US" }] },
        "capabilities" => { "transfers" => "active" },
      )))

      Sponsors::SyncStripeAccountDetails.call(account)

      assert_predicate account.reload, :verified_verification_status?
      refute_predicate account, :tax_reporting_capability?
    end

    test "updates country_of_residence on Sponsors listing when Stripe account is active" do
      Stripe::Account.stubs(:retrieve).returns(@details_response)
      @sponsors_listing.update_attribute(:country_of_residence, nil)
      assert_predicate @account, :active?

      Sponsors::SyncStripeAccountDetails.call(@account)

      assert_equal "US", @sponsors_listing.reload.country_of_residence
    end

    test "does not update country_of_residence on Sponsors listing when Stripe account is inactive" do
      Stripe::Account.stubs(:retrieve).returns(@details_response)
      @sponsors_listing.update_attribute(:country_of_residence, nil)
      @account.update!(active: false)

      Sponsors::SyncStripeAccountDetails.call(@account)

      assert_nil @sponsors_listing.reload.country_of_residence
    end

    test "raises exception and updates count in DataDog when listing update fails" do
      Stripe::Account.stubs(:retrieve).returns(@details_response)
      @sponsors_listing.update!(billing_country: nil, country_of_residence: nil)
      SponsorsListing.any_instance.stubs(:save).returns(false)
      SponsorsListing.any_instance.stubs(:errors).returns(stub(full_messages: ["o noes"]))

      error = assert_difference(-> { GitHub.dogstats.increments("stripe.account_sync_error").size }) do
        assert_no_difference(-> { GitHub.dogstats.increments("stripe.account_sync").size }) do
          assert_raises(Billing::StripeConnect::Account::SyncError) do
            Sponsors::SyncStripeAccountDetails.call(@account)
          end
        end
      end

      assert_equal "Failed to update Sponsors listing for maintainer #{@sponsors_listing.sponsorable_login}: tried " \
        "to change billing country from blank to CA, country of residence from blank to US. Stripe " \
        "account: #{@account.stripe_account_id}. o noes", error.message
      expected_datadog_tags = ["payable_type:SponsorsListing", "active:true", "has_email:false",
        "verification_status:verified"]
      assert_equal 1, GitHub.dogstats.increments("stripe.account_sync_error")
        .count { |x| x.tags.to_a == expected_datadog_tags }
    end

    test "does not call Stripe API if account details are already provided" do
      webhook = create(
        :stripe_webhook,
        :account_updated,
        object: { id: "acct_1234" },
        account: @account.stripe_account_id,
      )
      event = ::Stripe::Event.construct_from(webhook.payload)
      account_details = event.data.object

      Stripe::Account.expects(:retrieve).never

      Sponsors::SyncStripeAccountDetails.call(@account, account_details: account_details)
    end

    test "does nothing if account is not associated with a Sponsors listing" do
      @account.sponsors_listing.destroy!
      @account.reload

      Stripe::Account.stubs(:retrieve).returns(@details_response)

      refute_predicate @account, :verified_verification_status?
      refute_predicate @account, :charges_enabled?
      refute_predicate @account, :payouts_enabled?
      assert_nil @account.country
      assert_nil @account.billing_country

      Sponsors::SyncStripeAccountDetails.call(@account)

      refute_predicate @account.reload, :verified_verification_status?
      refute_predicate @account, :charges_enabled?
      refute_predicate @account, :payouts_enabled?
      assert_nil @account.country
      assert_nil @account.billing_country
    end

    test "publishes draft sponsors listing when all information is present" do
      details_hash = @details_hash
      details_hash["additional_verifications"] = {
        "us_w8_or_w9": {
          "requested_at": 3.days.ago,
          "status": "verified"
        }
      }
      details_response = Stripe::Account.construct_from(@details_hash)
      Stripe::Account.stubs(:retrieve).returns(details_response)

      user = create(:user, :sponsors_publishable)

      listing = user.sponsors_listing
      stripe_account = listing.active_stripe_connect_account

      assert_predicate listing, :can_publish?

      # clear events from listing creation
      reset_hydro

      Sponsors::SyncStripeAccountDetails.call(stripe_account)

      assert_predicate listing.reload, :approved?

      expected_message = {
        user: Hydro::EntitySerializer.user(listing.sponsorable),
        action: "APPROVED",
        automated: true,
      }

      assert_hydro_published_partial(expected_message, schema: "github.sponsors.v0.AccountStatusChange")
      assert_hydro_messages(count: 1, schema: "github.sponsors.v0.AccountStatusChange")
    end

    test "does not attempt to publish listing that is not in draft state" do
      details_hash = @details_hash
      details_hash["additional_verifications"] = {
        "us_w8_or_w9": {
          "requested_at": 3.days.ago,
          "status": "verified"
        }
      }
      details_response = Stripe::Account.construct_from(@details_hash)
      Stripe::Account.stubs(:retrieve).returns(details_response)

      user = create(:user, :sponsors_auto_approvable)

      listing = user.sponsors_listing
      stripe_account = listing.active_stripe_connect_account

      refute_predicate listing, :can_publish?

      SponsorsListing.any_instance.expects(:publish!).never

      Sponsors::SyncStripeAccountDetails.call(stripe_account)

      refute_predicate listing.reload, :approved?
    end
  end
end
