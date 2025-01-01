# typed: true
# frozen_string_literal: true

# This job handles actions related to open pull requests that should occur
# upon push, but independently of pull request synchronization.
class PushHandleMatchingPullRequestsJob < ApplicationJob
  queue_as :push_handle_matching_pull_requests

  resolve_tenant_context do |_push_id, repository_id|
    repository = Repositories::Public.get_active_or_deleted(repository_id)
    if repository
      Business.find_by(id: repository.tenant_id)
    end
  end

  RETRYABLE_ERRORS = [
    *Resiliency::Response::UnavailableExceptions, #recoverable exceptions
    ActiveRecord::ConnectionTimeoutError,
    ActiveRecord::QueryCanceled,
    ActiveRecord::RecordNotFound
  ]

  retry_on(*RETRYABLE_ERRORS, wait: :polynomially_longer)
  retry_on_dirty_exit

  def perform(repository_id, before: nil, after: nil, ref: nil, pushed_at: nil, pusher: nil)
    repository = Repositories::Public.get_active_or_deleted(repository_id)
    return unless repository.present?

    matching_open_pull_requests_to_update(repository_id, ref, before, after) do |pull_request|
      pull_request.enqueue_auto_merge_job_if_enabled

      pr_push_notification = PullRequestPushNotification.new(
        pull_request: pull_request,
        before: before,
        after: after,
        ref: ref,
        pushed_at: pushed_at,
        pusher: pusher
      )

      GitHub.newsies.trigger(pr_push_notification, event_time: pr_push_notification.created_at)
    end
  end

  # Public: Finds open pull requests matching the repository_id, ref, before, after.
  #
  # repository_id - Integer id of the pull request's head repository
  # ref           - String name of the ref (ex. "refs/heads/topic")
  # before        - String SHA of the ref before the push
  # after         - String SHA of the ref after the push
  #
  # Returns the matching PullRequests.
  def matching_open_pull_requests_to_update(repository_id, ref, before, after, &block)
    GitHub.dogstats.time("push", tags: ["action:find_open_pulls"]) do
      pulls = PullRequest.open_pulls.where(head_repository_id: repository_id, head_ref: Git::Ref.safe_ref_name(ref_names: ref))

      pulls.find_each do |pull|
        begin
          next if pull.spammy?
          # If we pushed to the head of a fork PR and the base is a soft deleted repository we shouldn't update the PR
          next if !pull.repository&.active?
          # Make sure the before OID is included in the PRs list of changed commits.
          # Otherwise we won't be able to render a diff for the notification.
          next if !pull.changed_commit_oids.include?(before)
          next if after == GitHub::NULL_OID

          pull_comparison = PullRequest::Comparison.find(
            pull: pull,
            start_commit_oid: before,
            end_commit_oid: after,
            base_commit_oid: pull.compare_repository.best_merge_base(pull.base_sha, after)
          )

          GitHub.dogstats.time("push", tags: ["action:diff_changed_check"]) do
            yield pull if pull_comparison&.diffs.present?
          end
        rescue GitRPC::Timeout, GitRPC::ObjectMissing => ex
          # If something goes wrong searching through the rev_list, assume the pull request needs attention
          false
        end
      end
    end
  end
end
