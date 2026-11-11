# frozen_string_literal: true

require "comments/rebase"
require "dependabot/pull_request_updater"

require "github_helpers"

class UpdatePullRequest # rubocop:disable Metrics/ClassLength
  class GitHubTreeCreationBug < StandardError; end

  class BranchProtectionInvalidSignatureError < StandardError; end

  attr_reader :pull_request, :updated_dependency_files, :new_base_commit_sha

  def initialize(pull_request:, updated_dependency_files:, new_base_commit_sha:)
    @pull_request = pull_request
    @updated_dependency_files = updated_dependency_files
    @new_base_commit_sha = new_base_commit_sha
  end

  def run
    # Ensure that updates that would be creating clashing changes on a branch
    # are not being processed concurrently.
    Restraints.for_branch_changes(repo: pull_request.repo, branch_name: github_details.head.ref) do
      remove_pr_message_addendum
      transition_pull_request_to_up_to_date

      return handle_edited if pr_has_been_edited? && !overwrite_edits?

      return handle_unchanged unless needs_rebase? || overwrite_edits?
      return unless update_pull_request

      enqueue_job_to_recheck_for_conflicts
      enqueue_job_to_merge if wants_merge?

      pull_request
    end
  rescue *SynchronizeRepoState::HANDLED_ERRORS
    SynchronizeRepoState.new(
      repo: pull_request.repo,
      event_source: "action.update_pull_request",
    ).run
  end

  private

  # If the base commit hasn't changed we check whether the current PR is
  # mergeable, as sometimes GitHub seems to get itself into a strange shape
  # that can be fixed by us pushing a rebased branch.
  def needs_rebase? # rubocop:disable Metrics/AbcSize
    return @needs_rebase if defined?(@needs_rebase)

    @needs_rebase = base_changed? || !github_details.mergeable

    Dependabot::Logger.info(
      msg: "Pull request #{pull_request.id} should #{'not ' unless @needs_rebase}be rebased",
      "code.namespace": "UpdatePullRequest",
      old_base_commit_sha: pull_request.base_commit_sha,
      new_base_commit_sha: new_base_commit_sha,
      monoliths_base_commit_sha: github_details.base.sha,
      base_changed: base_changed?,
      same_base_commit_between_services: github_details.base.sha == pull_request.base_commit_sha,
      monoliths_head_commit_sha: github_details.head.sha,
      monoliths_merge_commit_sha: github_details.merge_commit_sha,
      mergeable_state: github_details.mergeable,
      mergeable: github_details.mergeable,
      needs_rebase: @needs_rebase,
      rebase_or_recreate: overwrite_edits? ? "recreate" : "rebase",
      **pull_request.telemetry_attributes,
    )

    @needs_rebase
  end

  def transition_pull_request_to_up_to_date
    Statesman::Machine.retry_conflicts do
      pull_request.transition_to(:up_to_date) if pull_request.in_state?(:updating)
    end
  end

  def base_changed?
    new_base_commit_sha != pull_request.base_commit_sha
  end

  def pr_has_been_edited?
    PullRequestCommits.new(pull_request: pull_request).
      pr_has_been_edited?(head_sha: github_details.head.sha)
  end

  def overwrite_edits?
    pull_request.
      pull_request_transitions.
      where(to_state: "updating").
      order(:sort_key).last.
      metadata["overwrite_edits"]
  end

  def handle_unchanged
    if wants_merge?
      enqueue_job_to_merge
    elsif requested_by_human?
      add_comment_to_pull_request(comment: Comments::Rebase::BASE_COMMIT_UNCHANGED)
    else
      log_info(Comments::Rebase::BASE_COMMIT_UNCHANGED)
    end
  end

  def update_pull_request
    updated_commit_sha = update_pull_request_on_github

    # If the update didn't happen (e.g., because the branch had been deleted),
    # just return `nil`.
    unless updated_commit_sha
      if requested_by_human?
        add_comment_to_pull_request(comment: Comments::Rebase::SOMETHING_WENT_WRONG)
      else
        log_info("Update failed")
      end

      return
    end

    pull_request.update!(
      head_commit_sha: updated_commit_sha,
      dependabot_commit_sha: updated_commit_sha,
      base_commit_sha: new_base_commit_sha,
    )
    UpdatePullRequestCiStatusJob.perform_later(
      pull_request: pull_request,
      refs_to_check: [updated_commit_sha, new_base_commit_sha],
    )

    updated_commit_sha
  end

  def github_details
    @github_details ||=
      installation_github_client.pull_request(
        pull_request.repo.github_id,
        pull_request.github_number,
        headers: headers,
      )
  end

  def headers
    return {} unless Dependabot.proxima?

    {
      "X-Serialize-Login" => "display",
    }
  end

  def handle_edited
    pull_request.update!(head_commit_sha: github_details.head.sha)

    if requested_by_human?
      add_comment_to_pull_request(comment: Comments::Rebase::PULL_REQUEST_EDITED)
    else
      log_info("Pull request has been edited by someone other than Dependabot")
    end
  end

  def requested_by_human?
    pull_request.most_recent_update_job.trigger_type == "manual_rebase"
  end

  def log_info(message)
    Dependabot::Logger.info(
      msg: message,
      "code.namespace": "UpdatePullRequest",
      requested_by_human: requested_by_human?,
      rebase_or_recreate: overwrite_edits? ? "recreate" : "rebase",
      **pull_request.telemetry_attributes,
    )
  end

  def update_pull_request_on_github
    updated_ref = Dependabot::PullRequestUpdater.new(
      source: repo_source,
      base_commit: new_base_commit_sha,
      old_commit: pull_request.dependabot_commit_sha,
      files: updated_dependency_files,
      credentials: credentials,
      pull_request_number: pull_request.github_number,
    ).update

    return if updated_ref.nil?

    updated_ref.object.sha
  rescue *GitHubHelpers::RETRYABLE_ERRORS
    retry_count ||= 0
    retry_count += 1
    raise if retry_count > 3

    retry
  rescue Dependabot::PullRequestUpdater::BranchProtected
    handle_protected_branch_error
  rescue Octokit::UnprocessableEntity => e
    handle_unprocessable_entity_error(e)
  end

  def handle_protected_branch_error
    msg = "Dependabot attempted to update this pull request, but because the "\
          "branch `#{github_details.head.ref}` is protected it was unable to "\
          "do so."
    return if previous_pr_comments.any? { |comment| comment.body.include?(msg) }

    add_comment_to_pull_request(comment: msg)
    nil
  end

  def add_comment_to_pull_request(comment:)
    CreateComment.new(pull_request: pull_request, comment_body: comment).run
  end

  def handle_unprocessable_entity_error(error)
    # A GitHub bug means we sometimes get transitory errors trying to create
    # a tree. We have retry logic in Dependabot Core, but sometimes it appears
    # to need exponential backoff to sort itself out.
    raise GitHubTreeCreationBug if error.message.include?("Tree SHA does not")

    raise BranchProtectionInvalidSignatureError if error.message.include?("Commits must have valid signatures")

    # An invalid gitmodules file (unrelated to any Dependabot changes) causes
    # an UnprocessableEntity error which we want to tell the user about.
    if error.message.include?("GitRPC::BadGitmodules")
      NotifyGitHubOfFailureJob.perform_later(
        update_job: pull_request.update_job,
        error_hash: { "error-type" => "bad_gitmodules", "error-detail" => nil },
      )
      return
    end

    raise
  end

  def previous_pr_comments
    installation_github_client.issue_comments(
      pull_request.repo.github_id,
      pull_request.github_number,
    )
  end

  def repo_source
    update_config = pull_request.update_config

    Dependabot::Source.new(
      provider: "github",
      repo: update_config.repo.full_name,
      branch: update_config.target_branch,
      api_endpoint: Dependabot::Application.target_github_api_endpoint(update_config.repo.account),
      hostname: Dependabot::Application.target_github_hostname(update_config.repo.account),
    )
  end

  def remove_pr_message_addendum
    # Remove the "Dependabot is rebasing this PR" comment, if present.
    regex = %r{\[//\]: # \(dependabot-start\).*\[//\]: # \(dependabot-end\)}m
    updated_body = github_details.body.gsub(regex, "").strip

    UpdatePullRequestBody.new(
      pull_request: pull_request,
      updated_body: updated_body,
    ).run
  end

  def enqueue_job_to_recheck_for_conflicts
    CheckPullRequestForConflictsJob.perform_later(
      pull_request: pull_request,
      event_source: "action.update_pull_request"
    )
  end

  def enqueue_job_to_merge
    return unless wants_merge?

    # We enqueue a job to merge in case this repo doesn't have status checks
    # (which would be how the merge normally gets triggered)
    MergePullRequestJob.
      set(wait_until: Time.now.utc + 10.seconds).
      perform_later(pull_request: pull_request)
  end

  def wants_merge?
    pull_request.merge_requested?
  end

  def credentials
    @credentials ||=
      begin
        registry_credentials =
          pull_request.update_config.
          registries.
          map(&:serialized_credentials)

        github_credentials = {
          "type" => "git_source",
          "host" => Dependabot::Application.target_github_hostname(pull_request.repo.account),
          "username" => "x-access-token",
          "password" => github_access_token,
        }

        [*registry_credentials, github_credentials]
      end
  end

  def github_access_token
    @github_access_token ||=
      GitHubHelpers.access_token_for(account: pull_request.repo.account)
  end

  def installation_github_client
    @installation_github_client ||=
      GitHubHelpers::ClientWithRetries.new(account: pull_request.repo.account)
  end
end
