# typed: true
# frozen_string_literal: true

class BulkRemoveOrgMemberWatchedRepositoriesJob < ApplicationJob
  include GitHub::Memoizer

  queue_as :remove_org_member_watched_repositories

  GROUP_SIZE = 1000

  attr_reader :organization_ids, :user
  # This is the bulk version of RemoveOrgMemberWatchedRepositoriesJob
  # IMPORTANT: It does not create restorable records for each repository
  # If you need that, use RemoveOrgMemberWatchedRepositoriesJob instead
  def perform(organization_ids:, user_id:)
    @organization_ids = organization_ids
    @user = User.find_by(id: user_id)

    watched_count = 0

    watched_repo_ids = T.let([], T::Array[Integer])
    repo_ids_to_clear.each_slice(GROUP_SIZE).map do |batch_repo_ids|
      list_subscriptions = GitHub.newsies.list_subscriptions(@user, batch_repo_ids)
      watched_repo_ids += list_subscriptions.map(&:list_id)

      # Deleting subscriptions from batch_repo_ids, instead of watched_repo_ids, to delete both threads and lists.
      # This is the logic consistent with the non-bulk version of the job,
      # under the notifications_cleanup_threads_on_member_change feature flag.
      lists = batch_repo_ids.map { |id| Notifications::Subject.new(type: "Repository", id: id) }
      Notifications::Subscriptions.async_delete_user_subscriptions_for_lists(user_id: user_id, lists: lists)
    end

    watched_count = watched_repo_ids.uniq.length

    GitHub.dogstats.histogram "newsies", watched_count, tags: ["action:clear_memberships", "type:watched"]
  end

  private

  memoize def repo_ids_to_clear
    all_orgs_private_repo_ids = Repository.where(organization_id: @organization_ids).private_scope.pluck(:id)
    all_orgs_private_repo_ids - repo_ids_visible_to_user(all_orgs_private_repo_ids)
  end

  def repo_ids_visible_to_user(repo_ids)
    associated_repository_ids = []
    repo_ids.each_slice(GROUP_SIZE).map do |group_ids|
      associated_ids = @user.associated_repository_ids(repository_ids: group_ids)
      associated_repository_ids.concat(associated_ids).uniq!
    end

    # Load all internal repositories for the user. This is only to exclude internal repos from being unwatched,
    # so it doesn't matter if we load Rando Business internal IDs when cleaning up a user from a non-associated org.
    associated_repository_ids |= user.internal_repositories.pluck(:id)
    associated_repository_ids
  end
end
