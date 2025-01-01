# typed: true
# frozen_string_literal: true

class SponsorsListing::PayoutsExport
  extend T::Sig
  include ActiveModel::Validations
  include GitHub::Memoizer

  CSV_HEADERS = [
    "payout id",
    "organization",
    "organization url",
    "payout bank",
    "payout description",
    "processed amount (USD)",
    "amount",
    "payout date",
  ].freeze

  attr_reader :sponsors_listing, :contact_email, :payout_id

  validates :sponsors_listing, :payout_id, presence: true
  validates :contact_email, presence: { message: "no contact email for your GitHub Sponsors account" }
  validate :is_fiscal_host
  validate :is_stripe_account_owner

  delegate :sponsorable, :sponsorable_login, to: :sponsors_listing

  # sponsors_listing - the SponsorsListing of a fiscal host
  # payout_id - the String ID of a Stripe::Payout
  # stripe_account - optional Billing::StripeConnect::Account related to the payout id, will use
  #                  the listing's active Stripe Connect account if omitted.
  sig do
    params(
      sponsors_listing: T.nilable(SponsorsListing),
      payout_id: T.nilable(String),
      stripe_account: T.nilable(Billing::StripeConnect::Account),
    ).void
  end
  def initialize(sponsors_listing:, payout_id:, stripe_account: nil)
    @sponsors_listing = sponsors_listing
    @contact_email = sponsors_listing&.contact_email_address
    @payout_id = payout_id
    @stripe_account = stripe_account
  end

  # actor - optional User who requested the export
  # recipient - optional User who should receive the export email; defaults to the sponsorable if omitted
  sig { params(actor: T.nilable(User), recipient: T.nilable(GitHubSponsors::Types::Sponsorable)).returns(T::Boolean) }
  def start_export_job(actor: nil, recipient: nil)
    return false unless valid?

    ExportSponsorsPayoutsJob.perform_later(
      sponsors_listing.sponsorable,
      actor: actor,
      payout_id: payout_id,
      recipient: recipient,
      stripe_account: stripe_account
    )

    true
  end

  sig { returns T.nilable(String) }
  def as_csv
    return unless valid?

    stripe_account = T.must_because(self.stripe_account) { "#valid? ensures non-nil" }
    load_payout_response = stripe_account.load_payout(payout_id)
    return "No data found" unless load_payout_response.success?

    payout = load_payout_response.result
    transactions_response = stripe_account.stripe_transactions_for_payout(payout.id)
    return "No data found" unless transactions_response.success?

    payout_transactions = transactions_response.result
    balances = Hash.new(Billing::Money.zero)

    payout_transactions.auto_paging_each do |txn|
      transfer = txn.source.source_transfer
      next if transfer.reversed?

      login = sponsorable_for_transfer(transfer).login
      balances[login] += amount_for_transfer(transfer)
    end

    # We track the transfers in USD, but to aid non-USD fiscal hosts we parcel the total amount in the
    # destination currency to each maintainer according to their share of the total USD amount.
    balances_total = balances.values.sum
    payout_total = Billing::Money.new(payout.amount, payout.currency)
    destination_amounts = balances.each_with_object({}) do |(login, balance), hash|
      hash[login] = (balance / balances_total) * payout_total
    end

    payout_date = Time.at(payout.arrival_date).to_date
    payout_bank_name = payout.destination.try(:bank_name) || "Unknown Payout Destination"

    CSV.generate(encoding: Encoding::UTF_8) do |csv|
      csv << CSV_HEADERS

      balances.each do |login, amount|
        # ordered based on the CSV_HEADERS constant:
        # payout id, organization, payout bank, payout description, processed amount, payout date
        csv << [
          payout.id,
          login,
          "https://github.com/#{login}",
          payout_bank_name,
          payout.statement_descriptor,
          amount.format,
          destination_amounts[login].format,
          payout_date,
        ]
      end
    end
  end

  sig { returns String }
  def filename
    "sponsors-#{sponsorable_login}-payouts-#{Date.current}.csv"
  end

  private

  sig { returns T.nilable(Billing::StripeConnect::Account) }
  memoize def stripe_account
    @stripe_account || sponsors_listing&.active_stripe_connect_account
  end

  sig { params(transfer: Stripe::Transfer).returns(GitHubSponsors::Types::Sponsorable) }
  def sponsorable_for_transfer(transfer)
    listing_id = transfer.metadata[:sponsors_listing_id]&.to_i
    # assume the sponsorable that owns the Stripe account received the transfer if no listing ID is present
    return sponsorable if listing_id.blank?

    listing = cached_listings_by_id[listing_id]
    return T.must(listing.sponsorable) if listing&.sponsorable

    listing = SponsorsListing.find_by(id: listing_id)
    return sponsorable unless listing&.sponsorable

    cached_listings_by_id[T.must(listing.id)] = listing
    T.must(listing.sponsorable)
  end

  sig { params(transfer: Stripe::Transfer).returns(Billing::Money) }
  def amount_for_transfer(transfer)
    amount = Billing::Money.new(transfer.amount, transfer.currency)
    reversed = if transfer.respond_to?(:amount_reversed)
      Billing::Money.new(T.unsafe(transfer).amount_reversed, transfer.currency)
    else
      Billing::Money.zero
    end

    amount - reversed
  end

  sig { returns T::Hash[Integer, SponsorsListing] }
  def cached_listings_by_id
    @cached_listings_by_id ||= sponsors_listing
      .child_listings
      .or(SponsorsListing.where(id: sponsors_listing.id)) # the fiscal host itself may also be sponsorable
      .includes(:sponsorable)
      .index_by(&:id)
  end

  sig { void }
  def is_fiscal_host
    unless sponsors_listing&.fiscal_host?
      errors.add(:sponsors_listing, "does not represent a supported fiscal host")
    end
  end

  sig { void }
  def is_stripe_account_owner
    if stripe_account&.sponsors_listing != sponsors_listing
      errors.add(:sponsors_listing, "does not own the specified Stripe Connect account")
    end
  end
end
