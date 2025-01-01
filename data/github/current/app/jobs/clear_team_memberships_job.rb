# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class ClearTeamMembershipsJob < ApplicationJob
  queue_as :team_remove_members

  locked_by timeout: 5.minutes, key: DEFAULT_LOCK_PROC

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  # The max number of accesses to clear per job.
  MAX_ACCESS_LIST_SIZE = 500

  # Maximum number of repository ids sent to sql in one call
  MAX_REPOSITORY_IDS = 100

  attr_reader :org_id, :org, :repo, :user, :access_list, :options
  attr_accessor :watched

  def self.allow_async_enqueues?
    false
  end

  # Handles the task of clearing all Organization membership info.
  #
  # org_id      - Integer ID of the Organization that has been affected.
  # access_list - Array of Integer IDs of dependent objects.  If removing
  #               a User, this is a list of Repository IDs.  If removing a
  #               Repo, this is a list of User IDs.
  # options     - Hash specifying the member.
  #               :user   - Integer of the User ID.
  #               :repo   - Integer of the Repository ID.
  # start       - Integer of access_list index to begin processing at

  def perform(org_id, access_list, options = {}, start: 0)
    @org_id = org_id
    @access_list = Array(access_list)
    @options = options.with_indifferent_access

    # If access_list is large, break it into smaller batches and enqueues the next job per batch to avoid
    # high execution times. Only next job is queued in order to do work sequentially.
    batch_finish = start + MAX_ACCESS_LIST_SIZE

    return unless @options["user"] || @options["repo"]

    @org = Organization.find_by(id: @org_id.to_i)
    @watched = 0

    # Take a subset of the overall access_list to perform now
    slice = @access_list[start...batch_finish]

    if @options["user"] && @user = User.find_by(id: @options["user"])
      # clearing a list of repositories for a specific user
      clear_repositories_for_user(slice)
    elsif @options["repo"]
      # @options["repo"] could be an id or a Repository object...
      repo_id = @options["repo"].try(:id) || @options["repo"]
      if @repo = Repositories.domain.by_id(repo_id)
        # clearing a list of users for a specific repository
        remove_repo_data(slice)
      end
    end

    # If the work was broken into batches, run this job again, starting at the number that was the previous
    # batch end
    if @access_list.size > batch_finish
      ClearTeamMembershipsJob.perform_later(org_id, @access_list, options, start: batch_finish)
    end

    GitHub.dogstats.histogram "newsies", slice&.size || 0, tags: ["action:clear_memberships", "type:count"]
    GitHub.dogstats.histogram "newsies", @watched, tags: ["action:clear_memberships", "type:watched"]
  end

  # Clear a list of repositories for a specific user:
  #
  # * unwatch any repos the user is watching
  # * unassign any issues the user is assigned to
  # * hide the user from the org if the user is still visible and no longer has access
  #
  def clear_repositories_for_user(repository_ids)
    batch_notify_repository_access_changed(@user, repository_ids)

    # this is duplicating the logic of Repository#pullable_by, but externally so it can be done in bulk.
    # ignore public repositories, since they remain pullable:
    public_repo_ids = Repository.public_scope.where(id: repository_ids).pluck(:id)

    # get the list of all of the private repos in this list that the user *can* access (via teams or ownership)
    private_repo_ids = repository_ids - public_repo_ids
    accessible_private_repo_ids = @user.associated_repository_ids \
      including: [:indirect, :owned], repository_ids: private_repo_ids

    # now we have the full list of the repos the user can pull
    pullable_repo_ids = public_repo_ids + accessible_private_repo_ids

    # and we can see what's left over
    repo_ids_to_clear = repository_ids - pullable_repo_ids
    return if repo_ids_to_clear.empty?

    clear_assigned_issues(repo_ids_to_clear)
    clear_watched_repositories(repo_ids_to_clear)
    clear_starred_repositories(repo_ids_to_clear)
    clear_org_member_details(org, user)
  end

  # Clears every team user from the team member's repo.
  #
  # user_ids - Array of Integer User IDs.
  #
  # Returns nothing.
  def remove_repo_data(user_ids)
    user_ids_without_access = []

    users = User.where(id: user_ids).order(:id)
    promises = []

    users.each do |user|
      batch_notify_repository_access_changed(user, [@repo.id])

      promise = repo.async_pullable_by?(user).then do |pullable|
        unless pullable
          user_ids_without_access << user.id
          with_write { user.unstar(repo) } if Stars.domain.repo_starred_by_user?(repo.id, user.id)
          with_write { user.clear_issue_assignments(scope: repo.issues) } # domain-isolation-query-violation:ignore:packages/issues (SELECT, UPDATE)
          clear_org_member_details(org, user)
        end
      end

      promises << promise
    end

    Promise.all(promises).then do
      increase_watched_count(user_ids_without_access.length)

      unless user_ids_without_access.empty?
        subject = Notifications::Subject.new(type: "Repository", id: @repo.id)
        with_write do
          Notifications::Subscriptions.async_delete_list_subscriptions_for_users(list: subject, user_ids: user_ids_without_access)
        end
      end
    end.sync
  end

  def clear_starred_repositories(repo_ids_to_clear)
    starred_repos = user.starred_repositories.where(id: repo_ids_to_clear)
    starred_repos.each do |starred_repo|
      with_write { user.unstar starred_repo }
    end
  end

  def clear_assigned_issues(repo_ids_to_clear)
    # Only clear assignments for repositories that are active and not archived
    # Clearing issue assignments from archived repositories will fail because they are read-only
    Repository.batched_scope(:id, values: repo_ids_to_clear, batch_size: MAX_REPOSITORY_IDS) { |scope| scope.active }.each do |repository|
      next if repository.archived?
      with_write { user.clear_issue_assignments(scope: repository.issues) } # domain-isolation-query-violation:ignore:packages/issues (SELECT, UPDATE)
    end
  end

  def clear_watched_repositories(repo_ids_to_clear)
    return if repo_ids_to_clear.empty?

    # don't lookup repositories, as they may no longer exist,
    # and even if they have we still wish to cleanup subscriptions
    repos_to_clear = repo_ids_to_clear.map do |id|
      Notifications::Subject.new(type: "Repository", id: id)
    end

    increase_watched_count(repos_to_clear.length)
    with_write do
      Notifications::Subscriptions.async_delete_user_subscriptions_for_lists(user_id: user.id, lists: repos_to_clear)
    end
  end

  def clear_org_member_details(org, user)
    begin
      user.reload
    rescue ActiveRecord::RecordNotFound
      return
    end

    return unless org
    return if org.direct_or_team_member?(user)
    with_write do
      org.conceal_member user
      GitHub.newsies.get_and_update_settings(user) do |settings|
        settings.email(org, nil)
      end
    end
  end

  private

  def increase_watched_count(increment)
    self.watched = watched + increment
  end

  def batch_notify_repository_access_changed(user, repo_ids)
    repo_ids.each_slice(MAX_REPOSITORY_IDS) do |chunk|
      notify_repository_access_changed(user, chunk)
    end
  end

  def notify_repository_access_changed(user, repo_ids)
    GlobalInstrumenter.instrument(GlobalEvents::User::REPOSITORY_ACCESS_CHANGED, {
      user: user,
      repository_ids: repo_ids,
    })
  end
end
