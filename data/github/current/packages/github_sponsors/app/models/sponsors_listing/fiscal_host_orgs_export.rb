# typed: true
# frozen_string_literal: true

class SponsorsListing::FiscalHostOrgsExport
  include ActiveModel::Validations

  CSV_HEADERS = [
    "Login",
    "Name",
    "Profile status",
    "Billing county",
    "Country of residence",
    "Joined waitlist on",
    "Profile published on",
  ].freeze

  attr_reader :sponsors_listing, :viewer

  validates :sponsors_listing, presence: true
  validates :viewer, presence: true
  validate :is_fiscal_host

  def initialize(sponsors_listing:, viewer:)
    @sponsors_listing = sponsors_listing
    @viewer = viewer
  end

  def as_csv
    return unless valid?

    org_listings = sponsors_listing
      .child_listings
      .preload(sponsorable: :profile)
      .filter_spam_for(viewer)
      .ordered_by_sponsorable_login

    CSV.generate(encoding: Encoding::UTF_8) do |csv|
      csv << CSV_HEADERS

      org_listings.each do |org_listing|
        csv << [
          org_listing.sponsorable_login,
          org_listing.sponsorable.profile_name,
          org_listing.current_state_name,
          org_listing.billing_country,
          org_listing.country_of_residence,
          org_listing.created_at.strftime("%Y-%m-%d"),
          org_listing.published_at&.strftime("%Y-%m-%d"),
        ]
      end
    end
  end

  def filename
    "sponsors-#{sponsors_listing.sponsorable_login}-orgs-#{Date.current}.csv"
  end

  private

  def is_fiscal_host
    unless sponsors_listing&.fiscal_host?
      errors.add(:sponsors_listing, "does not represent a supported fiscal host")
    end
  end
end
