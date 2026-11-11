# frozen_string_literal: true

require "github_helpers"

class HandleRecreateRequestJob < ApplicationJob
  queue_as :default
  default_retries_for_idempotent_jobs

  # Retry over the next 2.5 hours, with exponential backoff
  T.unsafe(self).include ActiveJob::Retry.new(
    strategy: RateLimitBackoffStrategy.new(
      limit: 10,
      retryable_exceptions:
        [*GitHubHelpers::RETRYABLE_ERRORS, Octokit::Unauthorized],
    ),
    callback: proc do |exception, _|
      next unless exception.is_a?(Octokit::Unauthorized)

      uncache_installation_client
    end,
  )

  attr_reader :pull_request

  def perform(pull_request:)
    @pull_request = pull_request

    return update_overwrite_status if pull_request.currently_updating?

    if github_details.merged
      comment_merged
      enqueue_job_to_resync_pr_state_if_necessary
      return
    end

    if github_details.state == "closed"
      comment_closed
      enqueue_job_to_resync_pr_state_if_necessary
      return
    end

    Statesman::Machine.retry_conflicts do
      update_pull_request_if_new_commits_or_edited_or_reasonable
    end
  rescue *SynchronizeRepoState::HANDLED_ERRORS
    SynchronizeRepoState.new(
      repo: pull_request.repo,
      event_source: "job.handle_recreate_request",
    ).run
  end

  private

  def update_overwrite_status
    transition = pull_request.last_transition
    raise "Expected updating PR!" unless transition.to_state == "updating"

    transition.metadata["overwrite_edits"] = true
    transition.save!
  end

  def enqueue_job_to_resync_pr_state_if_necessary
    current_state = pull_request.current_state.to_sym
    return if github_details.merged && current_state == :merged
    return if github_details.state == "closed" && current_state == :closed

    ResyncPrStateJob.perform_later(pull_request: pull_request)
  end

  def pr_has_been_edited?
    PullRequestCommits.new(pull_request: pull_request).pr_has_been_edited?(
      head_sha: github_details.head.sha,
      exclude_skip_commits: false
    )
  end

  def enqueue_job_to_resync_pr_state
    ResyncPrStateJob.perform_later(pull_request: pull_request)
  end

  def github_details
    @github_details ||=
      installation_github_client.pull_request(
        pull_request.repo.github_id,
        pull_request.github_number,
      )
  end

  def update_pull_request_if_new_commits_or_edited_or_reasonable
    return comment_deleted if pull_request.update_config.in_state?(:deleted)
    return update_pull_request if github_details.mergeable_state == "behind"
    return update_pull_request if pr_has_been_edited?
    return update_pull_request if new_commits?(github_details.base.ref)
    return update_pull_request if default_branch_changed?(github_details)
    return update_pull_request if fewer_than_five_recreates_in_last_24_hours?

    comment_already_up_to_date(github_details.base.ref)
  end

  def comment_deleted
    comment = "The dependabot.yml entry that created this PR has been deleted so this PR can't be recreated. " \
              "Please close the PR so Dependabot can create a new one with the current dependabot.yml."
    comment_on_pull_request(comment)
  end

  def comment_edited
    comment = "Looks like this PR has been edited by someone other than "\
              "Dependabot. That means I can't rebase it - sorry!"
    comment_on_pull_request(comment)
  end

  def comment_merged
    dependency_ref =
      if pull_request.multiple_dependencies? then "these dependencies"
      else
        "`#{pull_request.updated_dependencies.first.name}`"
      end

    comment = "Looks like this PR has already been merged. If you've moved "\
              "back to an older version of #{dependency_ref} a new PR will be "\
              "created next time Dependabot checks your dependencies."
    comment_on_pull_request(comment)
  end

  def comment_closed
    comment = "Looks like this PR is closed. If you re-open it I'll "\
              "rebase it as long as no-one else has edited it (you can use "\
              "`@dependabot reopen` if the branch has been deleted)."
    comment_on_pull_request(comment)
  end

  def comment_already_up_to_date(target_branch)
    comment = "Looks like this PR is already up-to-date with "\
              "#{target_branch}, and has been recreated more than 5 times in "\
              "the last 24 hours!"
    comment_on_pull_request(comment)
  end

  def comment_on_pull_request(comment)
    CreateComment.new(pull_request: pull_request, comment_body: comment).run
  end

  def new_commits?(target_branch)
    last_commit = installation_github_client.commit(
      pull_request.repo.github_id,
      target_branch,
    )

    pull_request.base_commit_sha != last_commit.sha
  end

  def default_branch_changed?(github_details)
    return false unless pull_request.update_config.target_branch.nil?

    github_details.base.repo.default_branch != github_details.base.ref
  end

  def fewer_than_five_recreates_in_last_24_hours?
    recreates_in_last_24_hours =
      pull_request.pull_request_transitions.
      where(created_at: 24.hours.ago..Time.zone.now).
      where(to_state: "updating").
      select { |t| t.metadata&.fetch("overwrite_edits", nil) }

    recreates_in_last_24_hours.count < 5
  end

  def update_pull_request
    EnqueueRebase.new(
      pull_request: pull_request,
      github_details: github_details,
      overwrite_edits: true,
      manual: true,
    ).run
  end

  def installation_github_client
    @installation_github_client ||=
      GitHubHelpers::ClientWithRetries.new(
        account: pull_request.repo.account,
      )
  end

  def uncache_installation_client
    GitHubHelpers.delete_cached_access_token_for(
      account: pull_request.repo.account,
    )
    @installation_github_client = nil
  end
end
