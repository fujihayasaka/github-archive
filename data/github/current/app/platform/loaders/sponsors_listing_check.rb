# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class SponsorsListingCheck < Platform::Loader
      def self.load(sponsorable_id)
        self.for.load(sponsorable_id)
      end

      def fetch(sponsorable_ids)
        approved_listings = SponsorsListing.with_approved_state.
          for_sponsorable_user_or_org(sponsorable_ids).
          pluck(:sponsorable_id)

        approved_listings.each_with_object(Hash.new(false)) do |sponsorable_id, result|
          result[sponsorable_id] = true
        end
      end
    end
  end
end
