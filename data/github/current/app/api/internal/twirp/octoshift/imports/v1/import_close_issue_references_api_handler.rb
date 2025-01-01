# typed: true
# frozen_string_literal: true

require "monolith-twirp-octoshift-imports"

module Api::Internal::Twirp::Octoshift
  module Imports
    module V1
      class ImportCloseIssueReferencesAPIHandler < Api::Internal::Twirp::Handler
        include Helpers::ErrorHandler
        include Imports::Helpers::ModelDelay

        MAX_THROTTLE_RETRIES = 5
        handles_service MonolithTwirp::Octoshift::Imports::V1::ImportCloseIssueReferencesAPIService
        allow_access_for :client, allowed_clients: %w[octoshift elm migrations_vnext]

        # Public: Implementation of the ImportCloseIssueReferences Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Octoshift::Imports::V1::ImportCloseIssueReferencesRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Octoshift::Imports::V1::ImportCloseIssueReferencesResponse, or a Twirp::Error.
        def import_close_issue_references(req, env)
          check_model_replication_delay!(CloseIssueReference)

          if req.close_issue_references.empty?
            return Twirp::Error.invalid_argument("must be non-empty", argument: "close_issue_references")
          end

          errors = []

          close_issue_references = req.close_issue_references.map.with_index do |close_issue_reference_req, index|
            if close_issue_reference_req.pull_request_id.zero?
              errors << { batch_index: index, error_message: "pull_request_id must be positive integer." }
              next
            end

            if close_issue_reference_req.issue_id.zero?
              errors << { batch_index: index, error_message: "issue_id must be positive integer." }
              next
            end

            pull_request = replica(PullRequest).find_by(id: close_issue_reference_req.pull_request_id)

            unless pull_request
              errors << { batch_index: index, error_message: "Pull Request not found." }
              next
            end

            issue = replica(Issue).find_by(id: close_issue_reference_req.issue_id)

            unless issue
              errors << { batch_index: index, error_message: "Issue not found." }
              next
            end

            unless Repository.active.where(id: issue.repository_id).exists?
              errors << { batch_index: index, error_message: "Repository not found." }
              next
            end

            build_close_issue_reference(pull_request, issue)
          end.compact

          CloseIssueReference.throttle_with_retry(max_retry_count: MAX_THROTTLE_RETRIES, skip_reporting: true) do
            ActiveRecord::Base.connected_to(role: :writing) do
              CloseIssueReference.insert_all(close_issue_references) unless close_issue_references.empty?
            end
          end

          { batch_validation_errors: errors }
        rescue Api::Internal::Twirp::Octoshift::Errors::HighReplicationDelay => error
          replication_delay_error_handler(error.delay, error.role)
        end

        private

        def build_close_issue_reference(pull_request, issue)
          CloseIssueReference.new(
            actor_id: pull_request.user.id,
            issue_id: issue.id,
            issue_repository_id: issue.repository.id,
            pull_request_author_id: pull_request.user.id,
            pull_request_id: pull_request.id,
            source: :xref,
            created_at: Time.now.utc,
            updated_at: Time.now.utc
          ).attributes
        end
      end
    end
  end
end
