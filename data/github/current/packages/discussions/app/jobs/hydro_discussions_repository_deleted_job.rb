# typed: true
# frozen_string_literal: true

class HydroDiscussionsRepositoryDeletedJob < Repositories::RepositoryHydroMessageJob
  queue_as :hydro_discussions_repository_deleted

  def perform
    with_write { repository.disassociate_from_org_level_discussions }
  end
end
