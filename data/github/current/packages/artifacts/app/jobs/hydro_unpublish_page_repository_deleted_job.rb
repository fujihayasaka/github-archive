# typed: true
# frozen_string_literal: true

class HydroUnpublishPageRepositoryDeletedJob < Repositories::RepositoryHydroMessageJob
  queue_as :hydro_unpublish_page_repository_deleted

  def perform
    with_write { repository.unpublish_page }
  end
end
