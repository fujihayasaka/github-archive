# typed: strict
# frozen_string_literal: true

module PullRequests
  module MergeCommit
    class DeleteMergeCommitsJob < ApplicationJob
      Errored = Class.new(StandardError)

      retry_on Errored, attempts: 10, wait: :polynomially_longer
      retry_on_dirty_exit

      use_primaries ApplicationRecord::IssuesPullRequests

      use_replicas ApplicationRecord::Collab,
        ApplicationRecord::Mysql5,
        ApplicationRecord::Repositories,
        ApplicationRecord::Spokes,
        ApplicationRecord::Mysql1


      queue_as :pull_request_create_merge_commits

      resolve_tenant_context do |pull_request|
        if repository = pull_request.repository
          Business.find_by(id: repository.tenant_id)
        end
      end

      sig { params(pull_request: PullRequest).void }
      def perform(pull_request)
        unless repository = pull_request.repository
          raise ActiveRecord::RecordNotFound
        end

        outcome = DeleteCommits::Service.new(
          pull_request:,
          repository:,
          requested_at: enqueued_at || Time.current,
        ).call

        case outcome
        when DeleteCommits::Service::Outcome::Error
          # Retry this multiple times until it finally fails.
          raise Errored
        end
      end
    end
  end
end
