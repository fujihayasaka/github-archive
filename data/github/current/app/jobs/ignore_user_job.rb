# typed: false
# frozen_string_literal: true

class IgnoreUserJob < ApplicationJob
  queue_as :ignore_user
  retry_on_dirty_exit

  BATCH_SIZE = 100

  def perform(user_id, blockee_id)
    return unless user = User.find_by_id(user_id.to_i)
    return unless blockee = User.find_by_id(blockee_id.to_i)

    with_write do
      user.unfollow(blockee)
      blockee.unfollow user

      user.rebuild_contributions
      blockee.rebuild_contributions
    end

    blockee_repos = blockee.repositories
    user_repos = user.repositories

    Repository.throttle do
      blockee_repos.find_each(batch_size: BATCH_SIZE) do |repo|
        with_write do
          repo.remove_member(user, user)
          user.unstar(repo)
        end
      end

      user_repos.find_each(batch_size: BATCH_SIZE) do |repo|
        with_write do
          blockee.unstar(repo)
          repo.remove_member(blockee, user)
        end
      end

      repo_ids = user_repos.pluck(:id)

      # Unsubscribe blockee from all user's repos, and delete existing notifications
      lists = repo_ids.map { |id| Notifications::Subject.new(type: "Repository", id: id) }
      with_write do
        Notifications::Subscriptions.async_delete_user_subscriptions_for_lists(user_id: blockee.id, lists: lists)

        # Unpin repositories owned by the blocker/blockee
        ProfilePinner.unpin(*blockee_repos, user: user, viewer: user)
        ProfilePinner.unpin(*user_repos, user: blockee, viewer: user)

        # Cancel any pending invitations for the blocked user.
        RepositoryInvitation.cancel_all_invitations_involving(
          repo_ids: repo_ids,
          user: blockee,
        )
      end
    end

    Sponsorship.throttle do
      with_write { user.cancel_sponsorships_from_and_to(blockee, actor: user, reason: :BLOCKED_USER) }
    end

    if user.organization?
      RepositoryInvitation.throttle do
        user.pending_invitations.where(invitee_id: blockee.id).find_each(batch_size: BATCH_SIZE) do |invitation|
          with_write { invitation.cancel(actor: user) }
        end
      end
    end

    # Remove account succession relationships, captured in SuccessorInvitation associations
    with_write { SuccessorInvitation.terminate_all(user, blockee) }

    # Remove the users from each other's memex projects.
    blockee_memexes = blockee.memex_projects
    user_memexes = user.memex_projects

    MemexProject.throttle do
      blockee_memexes.find_each(batch_size: BATCH_SIZE) do |memex|
        with_write { memex.remove_collaborators([user]) }
      end

      user_memexes.find_each(batch_size: BATCH_SIZE) do |memex|
        with_write { memex.remove_collaborators([blockee]) }
      end
    end

    # Remove the users from each other's projects.
    blockee_projects = blockee.projects
    user_projects = user.projects

    Project.throttle do
      # Only revoke blocker's permissions from blockee's projects if the blocker is not an org,
      # since orgs can't be granted access to projects.
      if user.user?
        blockee_projects.find_each(batch_size: BATCH_SIZE) do |project|
          with_write { project.update_user_permission(user, nil) }
        end
      end

      user_projects.find_each(batch_size: BATCH_SIZE) do |project|
        with_write { project.update_user_permission(blockee, nil) }
      end
    end
  end
end
