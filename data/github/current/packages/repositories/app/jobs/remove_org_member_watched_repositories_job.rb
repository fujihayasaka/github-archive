# typed: true
# frozen_string_literal: true

class RemoveOrgMemberWatchedRepositoriesJob < LegacyRemoveOrgMemberDataJob
  include GitHub::Memoizer

  queue_as :remove_org_member_watched_repositories
  retry_on_dirty_exit

  GROUP_SIZE = 1000

  # For a given @user, unwatches repositories with ids in repos_to_clear.
  # Saves a restorable archive of each cleared record before clearing.
  # options is used by the base class it is a hash of { "organization_id" => value, "user_id" => value }
  def perform(options)
    watched = 0

    Repository
      .where(organization_id: org.id)
      .private_scope
      .pluck(Arel.sql("/*vt+ IGNORE_MAX_MEMORY_ROWS=1 */ id"))
      .in_groups_of(GROUP_SIZE, false)
      .map do |ids|
      org_repos = repo_to_clear(ids)
      repo_to_clear_ids = org_repos.collect(&:id)
      response = GitHub.newsies.list_subscriptions(user, repo_to_clear_ids)
      next unless response.success?

      tracked_repo_ids = response.map(&:list_id)
      tracked_repo_to_clear_ids = (tracked_repo_ids & repo_to_clear_ids)

      repos = org_repos.select { |org_repo| tracked_repo_to_clear_ids.include?(org_repo.id) }
      repos = with_subscription_decorations(repos, response)
      with_write { restorable.save_watched_repositories(repos) }
      watched += repos.length

      lists = repo_to_clear_ids.map { |id| Notifications::Subject.new(type: "Repository", id: id) }
      Notifications::Subscriptions.async_delete_user_subscriptions_for_lists(user_id: user.id, lists: lists)
    end

    with_write { restorable.save_watched_repositories_complete }
    GitHub.dogstats.histogram "newsies", watched, tags: ["action:clear_memberships", "type:watched"]
  end

  private

  def repo_to_clear(org_repo_ids)
    inaccessible_org_repo_ids = org_repo_ids - repo_ids_visible_to_user
    Repository.where(id: inaccessible_org_repo_ids).all
  end

  memoize def repo_ids_visible_to_user
    # rubocop:todo GitHub/DontCallAssociatedRepositoryIdsUnbounded
    accessible_repository_ids = user.associated_repository_ids(
      organization: org
    )
    # rubocop:enable GitHub/DontCallAssociatedRepositoryIdsUnbounded

    if org.supports_internal_repositories? && user.business_ids.include?(org.business.id)
      accessible_repository_ids |= org.internal_repositories.ids
    end

    accessible_repository_ids
  end

  # Private: Update repositories with subscription decorations.
  #
  # For each Repository in REPOSITORIES, decorates the
  # object with subscription details including ignored status,
  # subscriber_id, and subscribed_at timestamp.
  #
  # The decoration data is taken from the corresponding subscription entry
  # in SUBSCRIPTIONS.
  #
  # repositories - an Array of Repositories
  # subscriptions - a Newsies::Responses::Array collection
  #
  # returns an Array of Repositories
  def with_subscription_decorations(repositories, subscriptions)
    Restorables::SubscriptionDetails
      .decorate_collection(repositories, subscriptions: subscriptions, subscriber_id: user.id)
  end
end
