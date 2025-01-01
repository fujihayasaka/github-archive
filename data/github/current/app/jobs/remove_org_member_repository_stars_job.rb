# typed: true
# frozen_string_literal: true

require "scientist"

class RemoveOrgMemberRepositoryStarsJob < LegacyRemoveOrgMemberDataJob
  include Scientist

  queue_as :remove_org_member_repository_stars

  BATCH_SIZE = 1000

  # For a given @user, goes through private org repositories that have stars
  # and are not pullable by the user, then removes those stars
  #
  # Saves a restorable archive of each cleared record before clearing.
  # options is used by the base class it is a hash of { "organization_id" => value, "user_id" => value }
  def perform(options)

    # CI only: ensure the bulk version of the job passes all the same tests as the non-bulk version
    if org.feature_enabled?(:remove_org_member_repo_stars_job_use_bulk_ci_only)
      BulkRemoveOrgMemberRepositoryStarsJob.perform_now(user_id: user.id, organization_ids: [org.id])
      return
    end

    starred_repos_to_remove = org_owned_starred_repos(options)
    starred_repos_to_remove.in_groups_of(BATCH_SIZE, false).map do |repos_batch|
      with_write do
        restorable.save_repository_stars(repos_batch)
        Star.throttle do
          repos_batch.each { |repo| @user.unstar(repo) }
        end
      end
    end

    with_write { restorable.save_repository_stars_complete }
  end

  def org_owned_starred_repos(options)
    repos_to_unstar = []
    return repos_to_unstar unless user.any_starred_repositories?

    org.org_repositories.private_scope.pluck(Arel.sql("/*vt+ IGNORE_MAX_MEMORY_ROWS=1 */ id")).in_groups_of(BATCH_SIZE, false).map do |ids|
      starred_repos_in_org = user.starred_repositories.where(id: ids).all
      next if starred_repos_in_org.empty?

      inaccessible_repos_in_batch = inaccessible_org_repos(starred_repos_in_org)
      repos_to_unstar << inaccessible_repos_in_batch
    end

    repos_to_unstar.flatten
  end
end
