# typed: true
# frozen_string_literal: true

require "test_helper"

class SponsorsListing::PayoutsExportTest < GitHub::TestCase
  VCR_SPONSORS_LISTING_ID = 3

  if GitHub.sponsors_enabled?
    fixtures do
      @fiscal_host_listing = create(:sponsors_listing, :approved, :with_stripe_account, :open_source_collective)
      @fiscal_host = @fiscal_host_listing.sponsorable

      @org = create(:organization, :sponsorable)
      @org.sponsors_listing.update!(parent_listing: @fiscal_host_listing)
    end

    setup do
      @fiscal_host_stripe_account = @fiscal_host_listing.active_stripe_connect_account
      @fiscal_host_stripe_account.update!(stripe_account_id: "acct_1IziWM2Q3WKZykUd") # matches VCR

      @fiscal_host_payout = VCR.use_cassette("stripe/fiscal_host_payout") do
        @fiscal_host_stripe_account.load_payout("po_1J4bWv2Q3WKZykUdVvKsPWRE").result
      end
      @transactions = VCR.use_cassette("stripe/list_balance_transactions") do
        @fiscal_host_stripe_account.stripe_transactions_for_payout(@fiscal_host_payout.id).result
      end
    end

    context "#as_csv" do
      test "returns a CSV of balances per fiscally hosted organization for a given Stripe payout" do
        export = SponsorsListing::PayoutsExport.new(
          sponsors_listing: @fiscal_host_listing,
          payout_id: @fiscal_host_payout.id,
        )

        Billing::StripeConnect::Account
          .any_instance
          .expects(:load_payout)
          .with(@fiscal_host_payout.id)
          .returns(Billing::StripeConnect::Account::APIResult.success(
            account: @fiscal_host_stripe_account,
            result: @fiscal_host_payout,
          ))

        Billing::StripeConnect::Account
          .any_instance
          .expects(:stripe_transactions_for_payout)
          .with(@fiscal_host_payout.id)
          .returns(Billing::StripeConnect::Account::APIResult.success(
            account: @fiscal_host_stripe_account,
            result: @transactions,
          ))

        # Stripe transactions VCR tape uses a Sponsors listing with a specific id,
        # and it's not particularly important whether this is a currently fiscally hosted
        # listing or not since over time that could change and we need to be able
        # to look backwards at past payouts.
        transfer_listing = SponsorsListing.find_by(id: VCR_SPONSORS_LISTING_ID) || \
          create(:sponsors_listing, id: VCR_SPONSORS_LISTING_ID)

        expected_amount = Billing::Money.new(
          @fiscal_host_payout.amount,
          @fiscal_host_payout.currency,
        ).format

        expected_payout_item = [
          @fiscal_host_payout.id,
          transfer_listing.sponsorable_login,
          "https://github.com/#{transfer_listing.sponsorable_login}",
          @fiscal_host_payout.destination.bank_name,
          @fiscal_host_payout.statement_descriptor,
          "\"#{expected_amount}\"",
          "\"#{expected_amount}\"",
          Time.at(@fiscal_host_payout.arrival_date).to_date,
        ].join(",")

        expected = <<~CSV
          #{SponsorsListing::PayoutsExport::CSV_HEADERS.join(",")}
          #{expected_payout_item}
        CSV

        assert_equal expected, export.as_csv
      end

      test "returns error when there was an issue loading the payout" do
        export = SponsorsListing::PayoutsExport.new(
          sponsors_listing: @fiscal_host_listing,
          payout_id: @fiscal_host_payout.id,
        )

        Billing::StripeConnect::Account
          .any_instance
          .expects(:load_payout)
          .with(@fiscal_host_payout.id)
          .returns(Billing::StripeConnect::Account::APIResult.failure(
            account: @fiscal_host_stripe_account,
            error: "boom",
          ))

        Billing::StripeConnect::Account
          .any_instance
          .expects(:stripe_transactions_for_payout)
          .never

        assert_equal "No data found", export.as_csv
      end

      test "returns error when there was an issue fetching the payout transactions" do
        export = SponsorsListing::PayoutsExport.new(
          sponsors_listing: @fiscal_host_listing,
          payout_id: @fiscal_host_payout.id,
        )

        Billing::StripeConnect::Account
          .any_instance
          .expects(:load_payout)
          .with(@fiscal_host_payout.id)
          .returns(Billing::StripeConnect::Account::APIResult.success(
            account: @fiscal_host_stripe_account,
            result: @fiscal_host_payout,
          ))

        Billing::StripeConnect::Account
          .any_instance
          .expects(:stripe_transactions_for_payout)
          .with(@fiscal_host_payout.id)
          .returns(Billing::StripeConnect::Account::APIResult.failure(
            account: @fiscal_host_stripe_account,
            error: "boom",
          ))

        assert_equal "No data found", export.as_csv
      end

      test "supports using inactive Stripe account" do
        inactive_stripe_account = create(:stripe_connect_account, :inactive, sponsors_listing: @fiscal_host_listing)

        export = SponsorsListing::PayoutsExport.new(
          sponsors_listing: @fiscal_host_listing,
          payout_id: @fiscal_host_payout.id,
          stripe_account: inactive_stripe_account
        )

        inactive_stripe_account
          .expects(:load_payout)
          .with(@fiscal_host_payout.id)
          .returns(Billing::StripeConnect::Account::APIResult.success(
            account: @fiscal_host_stripe_account,
            result: @fiscal_host_payout,
          ))

        inactive_stripe_account
          .expects(:stripe_transactions_for_payout)
          .with(@fiscal_host_payout.id)
          .returns(Billing::StripeConnect::Account::APIResult.success(
            account: @fiscal_host_stripe_account,
            result: @transactions,
          ))

        export.as_csv
      end
    end

    context "#valid?" do
      test "validates listing is given" do
        export = SponsorsListing::PayoutsExport.new(
          sponsors_listing: nil,
          payout_id: "payout_id",
        )

        refute_predicate export, :valid?
        assert_includes export.errors[:sponsors_listing], "can't be blank"
      end

      test "validates that Sponsors listing is for a supported fiscal host" do
        listing = create(:sponsors_listing, :for_org)

        export = SponsorsListing::PayoutsExport.new(
          sponsors_listing: listing,
          payout_id: "payout_id",
        )

        refute_predicate export, :valid?
        assert_includes export.errors[:sponsors_listing], "does not represent a supported fiscal host"
      end

      test "validates presence of payout_id" do
        export = SponsorsListing::PayoutsExport.new(
          sponsors_listing: @fiscal_host_listing,
          payout_id: nil,
        )

        refute_predicate export, :valid?
        assert_includes export.errors[:payout_id], "can't be blank"
      end

      test "validates ownership of Stripe Connect account" do
        unowned_stripe_account = create(:stripe_connect_account)

        export = SponsorsListing::PayoutsExport.new(
          sponsors_listing: @fiscal_host_listing,
          payout_id: nil,
          stripe_account: unowned_stripe_account
        )

        refute_predicate export, :valid?
        assert_includes export.errors[:sponsors_listing], "does not own the specified Stripe Connect account"
      end
    end

    context "#start_export_job" do
      test "enqueues the ExportSponsorsPayoutsJob with the active stripe connect account by default" do
        export = SponsorsListing::PayoutsExport.new(
          sponsors_listing: @fiscal_host_listing,
          payout_id: "payout_id",
        )

        assert_enqueued_with(
          job: ExportSponsorsPayoutsJob,
          args: [
            @fiscal_host,
            {
              actor: nil,
              payout_id: "payout_id",
              recipient: nil,
              stripe_account: @fiscal_host_listing.active_stripe_connect_account,
            }
          ],
        ) do
          export.start_export_job
        end
      end

      test "passes along the specified recipient, actor, and stripe account" do
        staff = create(:staff_admin_user)
        inactive_stripe_account = create(:stripe_connect_account, :inactive, sponsors_listing: @fiscal_host_listing)
        export = SponsorsListing::PayoutsExport.new(
          sponsors_listing: @fiscal_host_listing,
          payout_id: "payout_id",
          stripe_account: inactive_stripe_account
        )

        assert_enqueued_with(
          job: ExportSponsorsPayoutsJob,
          args: [
            @fiscal_host,
            {
              actor: staff,
              payout_id: "payout_id",
              recipient: staff,
              stripe_account: inactive_stripe_account,
            }
          ],
        ) do
          export.start_export_job(actor: staff, recipient: staff)
        end
      end

      test "does NOT enqueue the ExportSponsorsPayoutsJob if invalid" do
        export = SponsorsListing::PayoutsExport.new(
          sponsors_listing: @fiscal_host_listing,
          payout_id: nil,
        )

        export.start_export_job

        assert_enqueued_jobs 0, only: ExportSponsorsPayoutsJob
      end
    end
  end
end
