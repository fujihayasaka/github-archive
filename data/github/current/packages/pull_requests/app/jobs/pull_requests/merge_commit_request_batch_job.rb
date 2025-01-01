# typed: strict
# frozen_string_literal: true
module PullRequests
  class MergeCommitRequestBatchJob < ApplicationJob
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
      # TODO: Noop until this is ready for deletion.
    end
  end
end
