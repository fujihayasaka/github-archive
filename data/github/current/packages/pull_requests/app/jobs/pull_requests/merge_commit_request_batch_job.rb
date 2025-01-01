# typed: strict
# frozen_string_literal: true
module PullRequests
  class MergeCommitRequestBatchJob < ApplicationJob
    extend T::Sig

    use_primaries ApplicationRecord::IssuesPullRequests

    use_replicas ApplicationRecord::Collab,
      ApplicationRecord::Mysql5,
      ApplicationRecord::Repositories,
      ApplicationRecord::Spokes,
      ApplicationRecord::Mysql1

    queue_as :commit_internal_batch_ref_updates

    resolve_tenant_context do |repository_id|
      Repositories::Public.find_active(repository_id)&.business
    end

    retry_on_dirty_exit

    RepoRepairingError = Class.new(StandardError)

    retry_on RepoRepairingError, wait: 5.seconds, attempts: 10

    locked_by timeout: 5.minutes, key: ->(job) {
      repository_id = job.arguments.first
      "commit-internal-batch-ref-updates-#{repository_id}"
    }

    sig { params(repository_id: Integer).void }
    def perform(repository_id)
      GitHub.logger.with_named_tags("gh.repo.id": repository_id) do
        unless repository = Repositories::Public.find_active(repository_id)
          return track("deleted_repository")
        end

        # Allow us to disable a repository from creating Merge Commits.
        if repository.feature_enabled?(:disable_merge_commit_request_batch_jobs)
          return track("disabled")
        end

        # Prevent piling on load when the repository is repairing. See existing: CreatePullRequestMergeCommitJob
        if repository.repairing?
          track("repository_repairing")
          raise RepoRepairingError
        end

        MergeCommit::Service.new(repository:).call

        clear_lock

        # Finally check to see if there are any outstanding requests, if so, reenqueue.
        request_count = MergeCommitRequest.where(repository_id: repository.id).count

        if request_count > 0
          self.class.perform_later(repository_id)
        end

        GitHub.dogstats.count("pull_requests.merge_commits.total_requests_count", request_count)
      end
    end

    private

    sig { params(name: String).void }
    def track(name)
      GitHub.logger.info("batch_cprmc_#{name}")
      GitHub.dogstats.increment("pull_requests.batch_merge_commits.#{name}")
    end
  end
end
