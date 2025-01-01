# typed: true
# frozen_string_literal: true

class RemoveUserFromRepoCleanupJob < ApplicationJob
  include Scientist

  queue_as :remove_user_repo_cleanup

  retry_on_dirty_exit

  # Perform the necessary cleanup when an outside collaborator is removed from a repository
  #
  # actor_id  - id of user who is doing the removal
  # member_id - id of user who is being removed
  # repo_id   - id of the repository
  def perform(actor_id:, member_id:, repo_id:)
    member = User.find_by(id: member_id)
    return unless member

    repo = Repository.find_by(id: repo_id)
    return unless repo

    actor = User.find_by(id: actor_id) || repo.owner

    if repo.pullable_by?(member)
      # If this user still has read access to the repository, we need to clear any existing PRs they have
      # where fork_collab_state = true since this grants them write access to branch in the head repository.
      DenyForkCollabStateForUserPullRequestsJob.perform_later(user_id: member_id, resource_id: repo_id, resource_class: repo.class.name)
    else
      with_write { repo.cancel_all_invitations_from_user(member, actor) }

      if actor == member || repo.private?
        list = Notifications::Subject.new(type: "Repository", id: repo_id)
        with_write do
          Notifications::Subscriptions.async_delete_user_subscriptions_for_lists(user_id: member_id, lists: [list])
        end
      end

      with_write do
        member.clear_issue_assignments(scope: repo.issues) # domain-isolation-query-violation:ignore:packages/issues (SELECT, UPDATE)
        member.unstar(repo)
        repo.remove_fork_for(member, actor)

        if repo.internal? && repo.network_root?
          repo.remove_from_forks(member, actor)
        end
      end
    end

    remove_user_from_business(repo, member)
  end

  def remove_user_from_business(repo, user)
    return if repo&.owner&.business.nil?

    business = repo.owner.business

    # This method will ensure the user is not removed if they should not be removed
    with_write do
      business.cleanup_removed_user(user, force: false)
    end
  end
end
