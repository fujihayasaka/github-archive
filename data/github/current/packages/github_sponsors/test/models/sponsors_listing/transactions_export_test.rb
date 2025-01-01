# typed: true
# frozen_string_literal: true

require "test_helper"

class SponsorsListing::TransactionsExportTest < GitHub::TestCase
  include ActionView::Helpers::NumberHelper

  fixtures do
    @osc_listing = create(:sponsors_listing, :open_source_collective, :with_stripe_account)
    @osc = @osc_listing.sponsorable

    @listing = create(:sponsors_listing, :approved, :with_fiscal_host, tier_count: 0, parent_listing: @osc_listing)
    @org = @listing.sponsorable
    @tier = create(:sponsors_tier, :published, sponsors_listing: @listing, monthly_price_in_cents: 1000) # $10

    @sponsorship = travel_to 2.years.ago do
      create :sponsorship, :with_billing_transaction_and_line_item, :with_payouts_ledger_entries,
        sponsorable: @org,
        tier: @tier,
        is_sponsor_opted_in_to_share_with_fiscal_host: true
    end

    @private_sponsorship = travel_to 2.days.ago do
      create :sponsorship, :private, :with_billing_transaction_and_line_item,
        :with_payouts_ledger_entries,
        sponsorable: @org,
        tier: @tier
    end

    travel_to 1.day.ago

    @invoiced_sponsorship_transfer = create :invoiced_sponsorship_transfer,
      sponsors_listing: @listing,
      transfer_created_at: Time.now
    @invoiced_sponsorship = create :sponsorship, :invoiced, :with_payouts_ledger_entries,
      invoiced_sponsorship_transfer: @invoiced_sponsorship_transfer

    travel_back

    @other_listing = create(:sponsors_listing, :approved, :with_stripe_account)
    @other_org = @other_listing.sponsorable
    @other_tier = @other_listing.default_tier

    @other_sponsorship = create :sponsorship, :with_billing_transaction_and_line_item, :with_payouts_ledger_entries,
      sponsorable: @other_org,
      tier: @other_tier
  end

  setup do
    skip unless GitHub.sponsors_enabled?
  end

  context "#as_csv" do
    test "returns CSV of all transactions associated with fiscal host" do
      export = SponsorsListing::TransactionsExport.new(sponsors_listing: @osc_listing, timeframe: :all)

      _, invoiced_ledger_entry, private_ledger_entry, public_ledger_entry = Billing::PayoutsLedgerEntry.transfer.most_recent_transaction_timestamp_first.to_a

      refute_nil public_ledger_entry
      public_ledger_entry = T.must(public_ledger_entry)
      expected_public = [
        public_ledger_entry.primary_reference_id, # stripe transfer id
        @org.login,
        "https://github.com/#{@org.login}",
        @sponsorship.sponsor.login, # sponsor handle
        @sponsorship.sponsor.publicly_visible_email(logged_in: true), # sponsor email
        "$10.00", # transferred amount
        public_ledger_entry.transaction_timestamp,
      ].join(",")

      refute_nil private_ledger_entry
      private_ledger_entry = T.must(private_ledger_entry)
      expected_private = [
        private_ledger_entry.primary_reference_id, # stripe transfer id
        @org.login,
        "https://github.com/#{@org.login}",
        "PRIVATE", # sponsor handle
        "PRIVATE", # sponsor email
        "$10.00", # transferred amount
        private_ledger_entry.transaction_timestamp,
      ].join(",")

      refute_nil invoiced_ledger_entry
      invoiced_ledger_entry = T.must(invoiced_ledger_entry)
      expected_invoiced = [
        invoiced_ledger_entry.primary_reference_id, # stripe transfer id
        @org.login,
        "https://github.com/#{@org.login}",
        @invoiced_sponsorship.sponsor.login,
        "PRIVATE", # sponsor email
        "$10.00", # transferred amount
        invoiced_ledger_entry.transaction_timestamp,
      ].join(",")

      expected = <<~CSV
        #{SponsorsListing::TransactionsExport::CSV_HEADERS.join(",")}
        #{expected_invoiced}
        #{expected_private}
        #{expected_public}
      CSV

      assert_equal expected, export.as_csv
    end

    test "filters out transactions based on given monthly timeframe" do
      export = SponsorsListing::TransactionsExport.new(sponsors_listing: @osc_listing, timeframe: :month)

      _, invoiced_ledger_entry, private_ledger_entry, public_ledger_entry = Billing::PayoutsLedgerEntry.transfer.most_recent_transaction_timestamp_first.to_a

      refute_nil private_ledger_entry
      private_ledger_entry = T.must(private_ledger_entry)
      expected_private = [
        private_ledger_entry.primary_reference_id, # stripe transfer id
        @org.login,
        "https://github.com/#{@org.login}",
        "PRIVATE", # sponsor handle
        "PRIVATE", # sponsor email
        "$10.00", # transferred amount
        private_ledger_entry.transaction_timestamp,
      ].join(",")

      refute_nil invoiced_ledger_entry
      invoiced_ledger_entry = T.must(invoiced_ledger_entry)
      expected_invoiced = [
        invoiced_ledger_entry.primary_reference_id, # stripe transfer id
        @org.login,
        "https://github.com/#{@org.login}",
        @invoiced_sponsorship.sponsor.login,
        "PRIVATE", # sponsor email
        "$10.00", # transferred amount
        invoiced_ledger_entry.transaction_timestamp,
      ].join(",")

      expected = <<~CSV
        #{SponsorsListing::TransactionsExport::CSV_HEADERS.join(",")}
        #{expected_invoiced}
        #{expected_private}
      CSV

      assert_equal expected, export.as_csv
    end

    test "returns results orderd by most recent transaction timestamp" do
      export = SponsorsListing::TransactionsExport.new(sponsors_listing: @osc_listing, timeframe: :all)

      _, invoiced_ledger_entry, private_ledger_entry, public_ledger_entry = Billing::PayoutsLedgerEntry.transfer.most_recent_transaction_timestamp_first.to_a

      refute_nil public_ledger_entry
      public_ledger_entry = T.must(public_ledger_entry)
      expected_public = [
        public_ledger_entry.primary_reference_id, # stripe transfer id
        @org.login,
        "https://github.com/#{@org.login}",
        @sponsorship.sponsor.login, # sponsor handle
        @sponsorship.sponsor.publicly_visible_email(logged_in: true), # sponsor email
        "$10.00", # transferred amount
        public_ledger_entry.transaction_timestamp,
      ].join(",")

      refute_nil private_ledger_entry
      private_ledger_entry = T.must(private_ledger_entry)
      expected_private = [
        private_ledger_entry.primary_reference_id, # stripe transfer id
        @org.login,
        "https://github.com/#{@org.login}",
        "PRIVATE", # sponsor handle
        "PRIVATE", # sponsor email
        "$10.00", # transferred amount
        private_ledger_entry.transaction_timestamp,
      ].join(",")

      refute_nil invoiced_ledger_entry
      invoiced_ledger_entry = T.must(invoiced_ledger_entry)
      expected_invoiced = [
        invoiced_ledger_entry.primary_reference_id, # stripe transfer id
        @org.login,
        "https://github.com/#{@org.login}",
        @invoiced_sponsorship.sponsor.login,
        "PRIVATE", # sponsor email
        "$10.00", # transferred amount
        invoiced_ledger_entry.transaction_timestamp,
      ].join(",")

      expected = <<~CSV
        #{SponsorsListing::TransactionsExport::CSV_HEADERS.join(",")}
        #{expected_invoiced}
        #{expected_private}
        #{expected_public}
      CSV

      assert_equal expected, export.as_csv
    end

    test "returns transactions belonging to inactive stripe accounts" do
      old_stripe_account = @osc_listing.active_stripe_connect_account
      old_stripe_account.update!(active: false)
      new_stripe_account = create(:stripe_connect_account, sponsors_listing: @osc_listing)

      assert_equal new_stripe_account, @osc_listing.reload.active_stripe_connect_account

      export = SponsorsListing::TransactionsExport.new(sponsors_listing: @osc_listing, timeframe: :all)

      _, invoiced_ledger_entry, private_ledger_entry, public_ledger_entry = Billing::PayoutsLedgerEntry.transfer.most_recent_transaction_timestamp_first.to_a

      refute_nil public_ledger_entry
      public_ledger_entry = T.must(public_ledger_entry)
      expected_public = [
        public_ledger_entry.primary_reference_id, # stripe transfer id
        @org.login,
        "https://github.com/#{@org.login}",
        @sponsorship.sponsor.login, # sponsor handle
        @sponsorship.sponsor.publicly_visible_email(logged_in: true), # sponsor email
        "$10.00", # transferred amount
        public_ledger_entry.transaction_timestamp,
      ].join(",")

      refute_nil private_ledger_entry
      private_ledger_entry = T.must(private_ledger_entry)
      expected_private = [
        private_ledger_entry.primary_reference_id, # stripe transfer id
        @org.login,
        "https://github.com/#{@org.login}",
        "PRIVATE", # sponsor handle
        "PRIVATE", # sponsor email
        "$10.00", # transferred amount
        private_ledger_entry.transaction_timestamp,
      ].join(",")

      refute_nil invoiced_ledger_entry
      invoiced_ledger_entry = T.must(invoiced_ledger_entry)
      expected_invoiced = [
        invoiced_ledger_entry.primary_reference_id, # stripe transfer id
        @org.login,
        "https://github.com/#{@org.login}",
        @invoiced_sponsorship.sponsor.login,
        "PRIVATE", # sponsor email
        "$10.00", # transferred amount
        invoiced_ledger_entry.transaction_timestamp,
      ].join(",")

      expected = <<~CSV
        #{SponsorsListing::TransactionsExport::CSV_HEADERS.join(",")}
        #{expected_invoiced}
        #{expected_private}
        #{expected_public}
      CSV

      assert_equal expected, export.as_csv
    end
  end
end
