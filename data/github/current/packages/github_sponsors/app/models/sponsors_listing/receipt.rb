# typed: strict
# frozen_string_literal: true

class SponsorsListing::Receipt
  extend T::Sig
  include GitHub::Memoizer

  # Public: Get a new receipt for a calendar year for the given Sponsorable.
  #
  # year   - the calendar year for this receipt period
  # tax_id - optional tax ID for this sponsorable
  sig do
    params(
      sponsors_listing: SponsorsListing,
      year: Integer,
      tax_id: T.nilable(String),
      sponsorable_address1: T.nilable(String),
      sponsorable_address2: T.nilable(String),
    ).returns(SponsorsListing::Receipt)
  end
  def self.for_listing_and_year(
    sponsors_listing:,
    year:,
    tax_id: nil,
    sponsorable_address1: nil,
    sponsorable_address2: nil
  )
    year = year
    start_date = DateTime.new(year, 1, 1)
    end_date = start_date.end_of_year

    new(
      sponsors_listing: sponsors_listing,
      start_date: start_date,
      end_date: end_date,
      tax_id: tax_id,
      sponsorable_address1: sponsorable_address1,
      sponsorable_address2: sponsorable_address2,
    )
  end

  # Public: Get a new receipt for the given Stripe payout.
  #
  # tax_id - optional tax ID for this sponsorable
  sig do
    params(
      sponsors_listing: SponsorsListing,
      stripe_payout: Billing::Stripe::Payout,
      start_date: DateTime,
      tax_id: T.nilable(String),
      sponsorable_address1: T.nilable(String),
      sponsorable_address2: T.nilable(String),
    ).returns(SponsorsListing::Receipt)
  end
  def self.for_payout(
    sponsors_listing:,
    stripe_payout:,
    start_date:,
    tax_id: nil,
    sponsorable_address1: nil,
    sponsorable_address2: nil
  )
    new(
      sponsors_listing: sponsors_listing,
      stripe_payout: stripe_payout,
      start_date: start_date,
      end_date: Time.at(stripe_payout.created).utc.to_datetime,
      tax_id: tax_id,
      sponsorable_address1: sponsorable_address1,
      sponsorable_address2: sponsorable_address2,
    )
  end

  sig do
    params(
      sponsors_listing: SponsorsListing,
      start_date: DateTime,
      end_date: DateTime,
      stripe_payout: T.nilable(Billing::Stripe::Payout),
      tax_id: T.nilable(String),
      sponsorable_address1: T.nilable(String),
      sponsorable_address2: T.nilable(String),
    ).void
  end
  def initialize(
    sponsors_listing:,
    start_date:,
    end_date:,
    stripe_payout: nil,
    tax_id: nil,
    sponsorable_address1: nil,
    sponsorable_address2: nil
  )
    @sponsors_listing = sponsors_listing
    @sponsorable_login = T.let(sponsors_listing.sponsorable_login, String)

    @start_date = start_date
    @end_date = end_date
    raise ArgumentError.new("Start date must be before the end date") if @start_date > @end_date

    @stripe_payout = stripe_payout
    raise ArgumentError.new("Sponsorable must have a Stripe account") unless @sponsors_listing.stripe_transfers_enabled?

    @tax_id = tax_id
    @sponsorable_address1 = sponsorable_address1
    @sponsorable_address2 = sponsorable_address2
  end

  sig { returns(SponsorsListing) }
  attr_reader :sponsors_listing

  sig { returns(String) }
  attr_reader :sponsorable_login

  sig { returns(DateTime) }
  attr_reader :start_date, :end_date

  sig { returns(T.nilable(Billing::Stripe::Payout)) }
  attr_reader :stripe_payout

  sig { returns(T.nilable(String)) }
  attr_reader :tax_id, :sponsorable_address1, :sponsorable_address2

  sig { returns(String) }
  def as_pdf
    PdfRenderer.new(self).render
  end

  sig { returns(String) }
  def pdf_filename
    "sponsors-#{sponsorable_login}-statement-#{Date.current}.pdf"
  end

  # Public: The total paid out to the Stripe account
  sig { returns(Billing::Money) }
  memoize def total_payout
    total_sponsorship
  end

  # Public: The total amount of sponsorship
  sig { returns(Billing::Money) }
  memoize def total_sponsorship
    payout = stripe_payout

    if payout.present?
      Billing::Money.new(payout.amount, payout.currency)
    else
      sponsors_listing.total_paid_out_by_year[start_date.year] || Billing::Money.zero
    end
  end
end
