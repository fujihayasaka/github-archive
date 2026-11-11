# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

# The purpose of this job is to reconcile the models with the index.
#
# To make this whole process faster, multiple repair jobs can be enqueued.
# The current offset into the marketplace_listings table is stored in redis.
# Access to this value is coordinated via a shared mutex. Don't spin up
# too many repair jobs otherwise you'll kill the database or the search
# index or both.
class RepairMarketplaceListingsIndexJob < Elastomer::RepairJob
  extend ClassMethods
  queue_as :index_bulk

  reconcile "marketplace_listing",
    fields: %w[updated_at],
    include: %i[categories regular_categories],
    reject: [:archived?],
    limit: 500,
    model_class: Marketplace::Listing
end
