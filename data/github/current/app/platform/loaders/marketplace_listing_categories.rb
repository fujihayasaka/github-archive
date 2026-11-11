# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class MarketplaceListingCategories < Platform::Loader
      def self.load(marketplace_listing_id)
        self.for.load(marketplace_listing_id)
      end

      def fetch(listing_ids)
        results = Marketplace::Category.connection.select_rows(Arel.sql(<<-SQL, listing_ids: listing_ids))
          SELECT marketplace_category_id, marketplace_listing_id
          FROM marketplace_categories_listings
          WHERE marketplace_listing_id IN (:listing_ids)
        SQL

        # results are arrays with category_id and listing_id pairs
        results = results.reduce({}) do |acc, res|
          acc[res.second] ||= []
          acc[res.second] << res.first
          acc
        end

        results.keys.reduce({}) do |acc, key|
          acc[key] = ::Marketplace::Category
            .joins(%q(
              LEFT JOIN marketplace_categories_listings
              ON marketplace_categories_listings.marketplace_category_id = marketplace_categories.id
            ))
            .where(id: results[key])
            .order("marketplace_categories_listings.id ASC")
            .distinct
          acc
        end
      end
    end
  end
end
