# typed: true
# frozen_string_literal: true

class Marketplace::ListingFeaturedOrganization < ApplicationRecord::Domain::Integrations
  include GitHub::Relay::GlobalIdentification
  self.table_name = "marketplace_listing_featured_organizations"

  # rubocop:todo Rails/InverseOf
  belongs_to :listing, class_name: "Marketplace::Listing", foreign_key: "marketplace_listing_id"
  # rubocop:enable Rails/InverseOf
  belongs_to :organization, required: true

  scope :approved, -> { where(approved: true) }
end
