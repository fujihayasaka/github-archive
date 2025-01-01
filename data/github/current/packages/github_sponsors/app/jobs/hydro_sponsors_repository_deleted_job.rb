# typed: true
# frozen_string_literal: true

class HydroSponsorsRepositoryDeletedJob < Repositories::RepositoryHydroMessageJob
  queue_as :hydro_sponsors_repository_deleted

  def perform
    with_write { repository.update_sponsors_listing_metadata_if_necessary }
    NullifyDependentRecordsJob.perform_later(T.must(Repository.name), T.must(repository.id), :sponsors_tiers)
    DeleteDependentRecordsJob.perform_later(
      T.must(Repository.name),
      T.must(repository.id),
      :sponsors_listing_featured_items,
      polymorphic_type_value: SponsorsListingFeaturedItem::featureable_types[:Repository]
    )
  end
end
