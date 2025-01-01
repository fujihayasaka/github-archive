# typed: true
# frozen_string_literal: true

class PullRequestSynchronizationJob < ApplicationJob
  queue_as :pull_request_synchronization
  retry_on_dirty_exit

  retry_on SpokesAPI::ResourceExhausted, wait: :polynomially_longer

  def perform(repository, ref, pusher, forced: false, before: nil, after: nil, push_options: nil, excluded_pull_ids: nil, pushed_at: nil)
    unless repository.active?
      GitHub.logger.info("pull_request_synchronization_job_no_repository")
      GitHub.dogstats.increment("pull_request.pull_request_synchronization_job.no_repository")
      return
    end

    with_write do
      PullRequest.synchronize_requests_for_ref(
        repository,
        ref,
        pusher,
        forced: forced,
        before: before,
        after: after,
        push_options: push_options,
        excluded_pull_ids: excluded_pull_ids,
        pushed_at: pushed_at,
      )
    end
  end
end
