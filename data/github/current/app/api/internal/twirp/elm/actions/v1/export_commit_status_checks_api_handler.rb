# typed: true
# frozen_string_literal: true

require "monolith-twirp-elm-actions"

module Api::Internal::Twirp::Elm
  module Actions
    module V1
      class ExportCommitStatusChecksAPIHandler < Api::Internal::Twirp::Handler

        DEFAULT_PER_PAGE = 30 # Default number of items per page for pagination
        PR_BATCH_MULTIPLIER = 5 # How many times larger the PR batch should be compared to the requested page size to ensure we get enough PRs for filtering
        MAX_PR_BATCH_SIZE = 1000 # Maximum size of the PR batch to avoid excessive memory usage

        handles_service MonolithTwirp::Elm::Actions::V1::ExportCommitStatusChecksAPIService
        allow_access_for :client, allowed_clients: %w[elm migrations_vnext]

        # Public: Implementation of the ExportCommitStatusChecks Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Elm::Actions::V1::ExportCommitStatusChecksRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns a Hash that Twirp will convert to a
        # MonolithTwirp::Elm::Actions::V1::ExportCommitStatusChecksResponse, or a Twirp::Error.
        def export_commit_status_checks(req, env)
          repo_id = req.repository_id
          return Twirp::Error.invalid_argument("must be non-empty", argument: "repository_id") if repo_id.nil? || repo_id == 0

          repository = if FeatureFlag.vexi.enabled?(:repos_by_id_api_twirp, default: false)
            ::Repositories.domain.by_id(repo_id)
          else
            Repository.find_by(id: repo_id)
          end
          if repository.nil?
            return Twirp::Error.not_found("Repository not found", argument: "repository_id").tap do |error|
              error.meta[:value] = repo_id.to_s
              error.meta[:elm_error_code] = "REPOSITORY_NOT_FOUND"
            end
          elsif repository.deleted?
            return Twirp::Error.not_found("Repository deleted", argument: "repository_id").tap do |error|
              error.meta[:value] = repo_id.to_s
              error.meta[:elm_error_code] = "REPOSITORY_DELETED"
            end
          end

          page = req.page.zero? ? 1 : req.page
          per_page = req.per_page.zero? ? DEFAULT_PER_PAGE : req.per_page

          # Get PR head SHAs if filtering is requested
          filter_shas = if req.should_only_export_latest
            pr_head_shas = get_pr_head_shas_for_repository_batched(repo_id, page, per_page)
            # Only apply filtering if there are actual PRs to filter to
            # If no PRs exist, we want to return all statuses, not none
            pr_head_shas.any? ? pr_head_shas : nil
          end

          # Calculate offset for the current page
          offset = (page - 1) * per_page

          # Get statuses for the current page using domain method
          # The domain method handles filtering but not pagination
          statuses = Statuses.domain.list_for_export(
            repository_id: repo_id,
            filter_shas: filter_shas,
            limit: per_page,
            offset: offset
          )

          # Get total count for pagination metadata
          total_count = Statuses.domain.count_for_export(
            repository_id: repo_id,
            filter_shas: filter_shas
          )

          status_checks = statuses.map { |status| build_status_check_hash(status) }

          build_export_response(status_checks, total_count)
        end

        private

        def get_pr_head_shas_for_repository_batched(repository_id, page, per_page)
          pr_batch_size = [per_page * PR_BATCH_MULTIPLIER, MAX_PR_BATCH_SIZE].min
          pr_offset = (page - 1) * pr_batch_size

          PullRequests::HeadShas.for_repository(
            repository_id: repository_id,
            limit: pr_batch_size,
            offset: pr_offset
          )
        end

        def map_state_to_protobuf_enum(state)
          case state
          when "success"
            :EXPORT_COMMIT_STATUS_CHECK_STATE_SUCCESS
          when "failure"
            :EXPORT_COMMIT_STATUS_CHECK_STATE_FAILURE
          when "pending"
            :EXPORT_COMMIT_STATUS_CHECK_STATE_PENDING
          when "error"
            :EXPORT_COMMIT_STATUS_CHECK_STATE_ERROR
          else
            :EXPORT_COMMIT_STATUS_CHECK_STATE_INVALID
          end
        end

        def build_status_check_hash(status)
          {
            id: status.id,
            resource_id: status.id.to_s,
            repository_resource_id: status.repository_id.to_s,
            commit_sha: status.commit_oid,
            creator_resource_id: status.creator_id.to_s,
            state: map_state_to_protobuf_enum(status.state),
            context: status.context,
            description: status.description,
            target_url: status.target_url,
            github_id: status.id.to_s,
            creator_id: status.creator_id.to_s,
            created_at: { seconds: status.created_at.to_i, nanos: 0 },
            updated_at: { seconds: status.updated_at.to_i, nanos: 0 }
          }
        end

        def build_export_response(status_checks, total_count)
          {
            success: true,
            export_commit_status_checks: status_checks,
            total_count: total_count,
            error_message: ""
          }
        end
      end
    end
  end
end
