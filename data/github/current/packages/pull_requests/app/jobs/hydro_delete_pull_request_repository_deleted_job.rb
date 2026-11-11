# typed: true
# frozen_string_literal: true

class HydroDeletePullRequestRepositoryDeletedJob < Repositories::RepositoryHydroMessageJob
  queue_as :hydro_delete_pull_request_repository_deleted

  def perform
    with_write { PullRequest.handle_deleted_repo(repository) }
  end
end
