# typed: true
# frozen_string_literal: true

# This job will purge all records of a user from the search index if that
# user is flagged as "spammy". Those records include:
#
# * user
# * repositories
# * releases
# * source code
# * commits
# * issues
# * issue comments
# * pull requests
# * pull request comments
# * milestones
# * gists
# * wikis
#
class PurgeSpammyFromSearchIndexJob < ApplicationJob
  queue_as :index_high

  locked_by key: ActiveJob::LockingJob::DEFAULT_LOCK_PROC, timeout: ActiveJob::LockingJob::DEFAULT_LOCK_TIMEOUT

  # Execute the user by executing this job. Pass in the user ID.
  #
  # user_id - The Integer ID of the user to purge.
  #
  def perform(user_id)
    @user = User.find_by(id: user_id)
    return unless @user && @user.spammy?

    Failbot.push "gh.user.id": @user.id

    purge_all
  end

  attr_reader :user

  def purge_all
    purge_user
    purge_issues_and_milestones
    purge_pull_requests
    purge_repositories
    purge_releases
    purge_code
    purge_commits
    purge_gists
    purge_wikis
    purge_workflow_runs
  end

  # Remove the given user from the search index.
  def purge_user
    purge_from_each_writable_index(Elastomer::Indexes::Users)
  end

  # Remove all issues and milestones authored by the user.
  def purge_issues_and_milestones
    purge_from_each_writable_index(Elastomer::Indexes::Issues)
  end

  # Remove all pull requests authored by the user.
  def purge_pull_requests
    purge_from_each_writable_index(Elastomer::Indexes::PullRequests)
  end

  # Remove all repositories owned by the user.
  def purge_repositories
    purge_from_each_writable_index(Elastomer::Indexes::Repos)
  end

  # Remove all releases authored by the user.
  def purge_releases
    purge_from_each_writable_index(Elastomer::Indexes::Releases)
  end

  # Remove all source code for the user.
  def purge_code
    # Remove from the blackbird code search indices
    user.repositories.each do |repo|
      GlobalInstrumenter.instrument("search_indexing.repository_deleted",
        change: :DISABLED,
        repository: repo,
      )
    end

    purge_from_each_writable_index(Elastomer::Indexes::CodeSearch)
  end

  # Remove all commits for the user.
  def purge_commits
    purge_from_each_writable_index(Elastomer::Indexes::Commits)
  end

  # Remove all gists from the search index for the given user.
  def purge_gists
    purge_from_each_writable_index(Elastomer::Indexes::Gists)
  end

  # Remove all wikis from the search index for the given user.
  def purge_wikis
    purge_from_each_writable_index(Elastomer::Indexes::Wikis)
  end

  # Update user_hidden in workflow runs where the actor is the given user.
  def purge_workflow_runs
    purge_from_each_writable_index(Elastomer::Indexes::WorkflowRuns)
  end

  def purge_from_each_writable_index(index_class)
    Elastomer.each_writable_index(index_class) do |config|
      begin
        index = index_class.new(config.name, config.cluster)
        index.purge_user(user)
      rescue StandardError => boom # rubocop:todo Lint/GenericRescue
        Failbot.report boom
      end
    end
  end
end
