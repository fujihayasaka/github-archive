# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class BulkRemoveOrgMemberRepositoryStarsJob < ApplicationJob
  queue_as :bulk_remove_org_member_repository_stars_job

  retry_on_dirty_exit

  BATCH_SIZE = 100

  # This is the bulk version of RemoveOrgMemberRepositoryStarsJob
  # IMPORTANT: It does not create restorable records for each starred repo
  # If you need that, use the non-bulk version of the job
  def perform(user_id:, organization_ids:)
    return if organization_ids.empty?
    return unless user = User.find_by(id: user_id)

    # stars for repos by this user
    star_ids_for_repos_by_user = Stars.domain.user_starred_repository_ids(user_id)
    return if star_ids_for_repos_by_user.empty?

    # starred repos by this user in these orgs that the user no longer has access to
    repos_to_unstar = Repository.repo_ids_not_visible_to_user_from_orgs(user, organization_ids, repo_ids: star_ids_for_repos_by_user)

    # iterate over the actual stars in batches and destroy them
    Star.stars_for_user_and_repos(user_id: user_id, repository_ids: repos_to_unstar).in_batches(of: BATCH_SIZE) do |star_batch|
      with_write do
        Star.throttle do
          # continuing to use destroy_all to invoke callbacks
          # if this job turns out to be slow or expensive,
          # we can switch to delete_all, but will need to introduce bulk versions of each callback
          # and invoke them manually
          star_batch.destroy_all
        end
      end
    end
  end
end
