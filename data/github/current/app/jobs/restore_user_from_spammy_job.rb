# typed: true
# frozen_string_literal: true

# This job will restore all records of a user to the search index after the
# spammy flag has been cleared. Those records include:
#
# * user
# * repositories
# * source code
# * commits
# * issues
# * issue comments
# * milestones
# * gists
# * wikis
#
class RestoreUserFromSpammyJob < ApplicationJob
  queue_as :index_high

  locked_by key: ActiveJob::LockingJob::DEFAULT_LOCK_PROC, timeout: ActiveJob::LockingJob::DEFAULT_LOCK_TIMEOUT

  # Restore the user by executing this job. Pass in the user ID.
  #
  # user_id - The Integer ID of the user to restore.
  #
  def perform(user_id)
    with_read do
      @user = User.find_by(id: user_id)
      return unless @user && !@user.spammy?

      Failbot.push "gh.user.id": @user.id

      restore_all
    end
  end

  attr_reader :user

  def restore_all
    restore_user
    restore_issues_and_milestones
    restore_pull_requests
    restore_repositories
    restore_releases
    restore_code
    restore_commits
    restore_gists
    restore_wikis
    restore_workflow_runs
  end

  # Restore the given user to the search index.
  def restore_user
    restore_to_each_writable_index(Elastomer::Indexes::Users)
  end

  # Restore all issues and milestones to the search index.
  def restore_issues_and_milestones
    restore_to_each_writable_index(Elastomer::Indexes::Issues)
  end

  # Restore all pull requests to the search index.
  def restore_pull_requests
    restore_to_each_writable_index(Elastomer::Indexes::PullRequests)
  end

  # Restore all repositories to the search index.
  def restore_repositories
    restore_to_each_writable_index(Elastomer::Indexes::Repos)
  end

  # Restore the user releases to the search index.
  def restore_releases
    restore_to_each_writable_index(Elastomer::Indexes::Releases)
  end

  # Restore all source code to the search index.
  def restore_code
    # Restore in blackbird code search by re-onboarding.
    user.repositories.each do |repo|
      GlobalInstrumenter.instrument("blackbird.repository.onboard", repository: repo)
    end

    restore_to_each_writable_index(Elastomer::Indexes::CodeSearch)
  end

  # Restore all commits to the search index.
  def restore_commits
    restore_to_each_writable_index(Elastomer::Indexes::Commits)
  end

  # Restore all gists to the search index for the given user.
  def restore_gists
    restore_to_each_writable_index(Elastomer::Indexes::Gists)
  end

  # Restore all wikis to the search index.
  def restore_wikis
    restore_to_each_writable_index(Elastomer::Indexes::Wikis)
  end

  # Update user_hidden in workflow runs where the actor is the given user.
  def restore_workflow_runs
    restore_to_each_writable_index(Elastomer::Indexes::WorkflowRuns)
  end

  def restore_to_each_writable_index(index_class)
    index_name = index_class.index_name
    GitHub.dogstats.time("restore_user_index.time", tags: ["index:" + index_name]) do
      Elastomer.each_writable_index(index_class) do |config|
        begin
          index = index_class.new(config.name, config.cluster)
          index.restore_user(user)
        rescue StandardError => boom # rubocop:todo Lint/GenericRescue
          Failbot.report boom
        end
      end
    end
  end
end
