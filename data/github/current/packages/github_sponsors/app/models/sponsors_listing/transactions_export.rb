# typed: true
# frozen_string_literal: true

class SponsorsListing::TransactionsExport
  CSV_HEADERS = [
    "stripe transfer id",
    "organization",
    "organization url",
    "sponsor handle",
    "sponsor email",
    "transferred amount",
    "transaction timestamp",
  ].freeze

  attr_reader :sponsors_listing, :timeframe

  def initialize(sponsors_listing:, timeframe: :month)
    @sponsors_listing = sponsors_listing
    @timeframe = timeframe
  end

  def as_csv
    sponsor_ids, sponsorable_ids = sponsor_and_sponsorable_ids
    preload_sponsorships(sponsor_ids, sponsorable_ids)

    CSV.generate(encoding: Encoding::UTF_8) do |csv|
      csv << CSV_HEADERS

      ledger_entries.each do |ledger_entry|
        sponsor = sponsor_for_ledger_entry(ledger_entry)
        next unless sponsor

        sponsorable = sponsorable_for_ledger_entry(ledger_entry)
        next unless sponsorable

        sponsorship = sponsorship_for_sponsor_id_and_sponsorable_id(sponsor.id, sponsorable.id)
        next unless sponsorship

        public_sponsorship = sponsorship.privacy_public?
        share_with_host = public_sponsorship && sponsorship
          .is_sponsor_opted_in_to_share_with_fiscal_host?

        csv << [
          ledger_entry.primary_reference_id,
          sponsorable.login,
          "https://github.com/#{sponsorable.login}",
          public_sponsorship ? sponsor.login : "PRIVATE",
          share_with_host ? sponsor.publicly_visible_email(logged_in: true) : "PRIVATE",
          transferred_amount_for_ledger_entry(ledger_entry).format,
          ledger_entry.transaction_timestamp
        ]
      end
    end
  end

  def filename
    date = all_time? ? "all-time" : Date.current
    "sponsors-#{sponsors_listing.sponsorable_login}-transactions-#{date}.csv"
  end

  def all_time?
    timeframe.to_sym == :all
  end

  private

  def sponsor_for_ledger_entry(ledger_entry)
    line_item = line_item_for_ledger_entry(ledger_entry)
    return line_item.user if line_item

    invoiced_transfer = invoiced_transfer_for_ledger_entry(ledger_entry)
    invoiced_transfer&.sponsor
  end

  def sponsorable_for_ledger_entry(ledger_entry)
    line_item = line_item_for_ledger_entry(ledger_entry)
    if line_item
      return line_item.subscribable.sponsorable
    end

    invoiced_transfer = invoiced_transfer_for_ledger_entry(ledger_entry)
    invoiced_transfer&.sponsorable
  end

  def transferred_amount_for_ledger_entry(ledger_entry)
    Billing::Money.new(ledger_entry.amount_in_subunits, ledger_entry.currency_code)
  end

  def sponsor_and_sponsorable_ids
    ids = ledger_entries.map { |ledger_entry| sponsor_and_sponsorabld_ids_for_ledger_entry(ledger_entry) }
    sponsor_ids, sponsorable_ids = ids.transpose.map(&:compact).map(&:uniq)
    [sponsor_ids, sponsorable_ids]
  end

  def sponsor_and_sponsorabld_ids_for_ledger_entry(ledger_entry)
    line_item = line_item_for_ledger_entry(ledger_entry)
    if line_item
      sponsor_id = line_item.billing_transaction.user_id
      sponsorable_id = line_item.subscribable.sponsorable_id
      return [sponsor_id, sponsorable_id]
    end

    invoiced_transfer = invoiced_transfer_for_ledger_entry(ledger_entry)
    if invoiced_transfer
      sponsor_id = invoiced_transfer.sponsor_id
      sponsorable_id = invoiced_transfer.sponsorable_id
      return [sponsor_id, sponsorable_id]
    end

    [nil, nil]
  end

  def line_item_for_ledger_entry(ledger_entry)
    line_item_key = [ledger_entry.billing_transaction_id,  ledger_entry.sponsors_listing_id]
    line_items_by_billing_transaction_and_listing[line_item_key]
  end

  def invoiced_transfer_for_ledger_entry(ledger_entry)
    invoiced_transfers_by_zuora_payment_id[ledger_entry.zuora_transaction_id]
  end

  def preload_sponsorships(sponsor_ids, sponsorable_ids)
    sponsorship_fields = %i(sponsor_id sponsorable_id privacy_level
      is_sponsor_opted_in_to_share_with_fiscal_host)
    @sponsorships_by_sponsor_id_and_sponsorable_id = ::Sponsorship.select(*sponsorship_fields)
      .where(sponsor_id: sponsor_ids, sponsorable_id: sponsorable_ids)
      .each_with_object({}) do |sponsorship, hash|
        hash[sponsorship.sponsor_id] ||= {}
        hash[sponsorship.sponsor_id][sponsorship.sponsorable_id] = sponsorship
      end
  end

  def sponsorship_for_sponsor_id_and_sponsorable_id(sponsor_id, sponsorable_id)
    sponsor_hash = @sponsorships_by_sponsor_id_and_sponsorable_id[sponsor_id]
    return unless sponsor_hash
    sponsor_hash[sponsorable_id]
  end

  def ledger_entries
    return @ledger_entries if defined?(@ledger_entries)

    scope = Billing::PayoutsLedgerEntry
      .transfer
      .for_stripe_account(sponsors_listing.stripe_connect_account_ids_for_self_or_fiscal_host)

    @ledger_entries = limit_timeframe(scope, field: :transaction_timestamp).most_recent_transaction_timestamp_first
  end

  def invoiced_transfers_by_zuora_payment_id
    return @invoiced_transfers_by_zuora_payment_id if defined?(@invoiced_transfers_by_zuora_payment_id)

    scope = InvoicedSponsorshipTransfer
      .includes(:sponsor, :sponsors_listing)
      .for_stripe_account(sponsors_listing.stripe_connect_account_ids_for_self_or_fiscal_host)

    scope = limit_timeframe(scope, field: :transfer_created_at)
    @invoiced_transfers_by_zuora_payment_id = scope.index_by(&:zuora_payment_id)
  end

  def line_items_by_billing_transaction_and_listing
    return @line_items_by_billing_transaction_and_listing if defined?(@line_items_by_billing_transaction_and_listing)

    scope = Billing::BillingTransaction::LineItem
      .includes(billing_transaction: :live_user)
      .preload(subscribable: { sponsors_listing: :sponsorable })
      .where(subscribable_id: tier_ids, subscribable_type: SponsorsTier.name)
      .order(:created_at)

    scope = limit_timeframe(scope, field: :created_at)
    @line_items_by_billing_transaction_and_listing = scope.index_by do |line_item|
      [
        line_item.billing_transaction_id,
        line_item.subscribable.sponsors_listing_id,
      ]
    end
  end

  def tier_ids
    SponsorsTier
      .joins(:sponsors_listing)
      .merge(sponsors_listing.child_listings)
      .pluck(:id)
  end

  def limit_timeframe(scope, field:)
    return scope if all_time?

    # default to last month
    now = Time.now
    end_date = now.end_of_day + 1.day
    start_date = now.beginning_of_day - 1.month

    scope.where(field => start_date..end_date)
  end
end
