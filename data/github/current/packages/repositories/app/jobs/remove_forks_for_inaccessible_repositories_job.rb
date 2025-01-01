# typed: true
# frozen_string_literal: true

class RemoveForksForInaccessibleRepositoriesJob < ApplicationJob
  queue_as :sync_organization_default_repository_permission

  def perform(repository_ids, user_ids)
    # This job is called in one of two ways:
    # 1. checking forks within a network of repos for a specific user (i.e. a user removed from a team)
    # 2. checking a repo for a list of users (i.e. a repo removed from a team)
    start = Time.current
    if user_ids.size < repository_ids.size
      remove_forks_by_user(user_ids, repository_ids)
    else
      remove_forks_by_repository(repository_ids, user_ids)
    end
  ensure
    GitHub.dogstats.timing_since("job.remove_forks_for_inaccessible_repositories.time", start)
  end

  # Check one (or a few) users with forks of many given repositories to
  # make sure they still have access to them. If not, remove the fork.
  def remove_forks_by_user(user_ids, repository_ids)
    User.where(id: user_ids).each do |user|
      # Find the forks of any of the given repositories owned by the user,
      # and see if they still have access to the parent.
      Repository.private_scope.where(parent_id: repository_ids).owned_by(user).includes(:parent).each do |user_fork|
        parent = user_fork.parent
        if !parent.pullable_by? user
          with_write { parent.remove_user_fork(user_fork) }
          GitHub.dogstats.increment("org.repo.archive_fork")
        end
      end
    end
  end

  # Check forks of one (or a few) repos to make sure many users retain access to them.
  def remove_forks_by_repository(repository_ids, user_ids)
    # Iterate each of the given repos, and for each find any forks owned by
    # the given users and check only those user-owned forks to see if the
    # user retains access to the parent repo.
    Repository.private_scope.where(id: repository_ids).each do |parent_repo|
      with_write { parent_repo.remove_inaccessible_forks_for(user_ids) }
    end
  end
end
