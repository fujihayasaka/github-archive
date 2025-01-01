# typed: true
# frozen_string_literal: true

require "monolith-twirp-elm-actions"

module Api::Internal::Twirp::Elm
  module Actions
    module V1
      # Handler for the MonolithTwirp::Elm::Actions::V1::ExportCheckSuitesAPIService
      class ExportCheckSuitesAPIHandler < Api::Internal::Twirp::Handler

        DEFAULT_PER_PAGE = 30 # Default number of items per page for pagination
        PR_BATCH_MULTIPLIER = 5 # How many times larger the PR batch should be compared to the requested page size to ensure we get enough PRs for filtering
        MAX_PR_BATCH_SIZE = 1000 # Maximum size of the PR batch to avoid excessive memory usage

        allow_access_for :client, allowed_clients: %w[elm migrations_vnext]
        handles_service MonolithTwirp::Elm::Actions::V1::ExportCheckSuitesAPIService

        # Public: Implementation of the ExportCheckSuites Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Elm::Actions::V1::ExportCheckSuitesRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response either as a
        # MonolithTwirp::Elm::Actions::V1::ExportCheckSuitesResponse, or a Twirp::Error.
        sig do
          params(
            req: MonolithTwirp::Elm::Actions::V1::ExportCheckSuitesRequest,
            env: T::Hash[String, T.untyped]
          ).returns(T.any(MonolithTwirp::Elm::Actions::V1::ExportCheckSuitesResponse, Twirp::Error))
        end
        def export_check_suites(req, env)
          repo_id = req.repository_id
          return Twirp::Error.invalid_argument("must be non-empty", argument: "repository_id") if repo_id == 0

          repository = if FeatureFlag.vexi.enabled?(:repos_domain_find_by, default: false)
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
            # If no PRs exist, we want to return all check suites, not none
            pr_head_shas.any? ? pr_head_shas : nil
          end

          # Calculate offset for the current page
          offset = (page - 1) * per_page

          # Get check suites for the current page using similar approach to check runs
          check_suites = get_check_suites_for_repository(
            repository_id: repo_id,
            filter_shas: filter_shas,
            limit: per_page,
            offset: offset
          )

          # Get total count for pagination metadata
          total_count = count_check_suites_for_repository(
            repository_id: repo_id,
            filter_shas: filter_shas
          )

          export_check_suites = check_suites.map { |check_suite| build_check_suite_hash(check_suite) }

          build_export_response(export_check_suites, total_count)
        rescue StandardError => e # rubocop:disable Lint/RescueException
          GitHub.logger.error("Failed to export check suites for repository #{repo_id}: #{e.message}")
          GitHub.logger.error(T.must(e.backtrace).join("\n")) if e.backtrace

          Twirp::Error.internal("Failed to export check suites").tap do |error|
            error.meta[:elm_error_code] = "INTERNAL_ERROR"
          end
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

        def get_check_suites_for_repository(repository_id:, filter_shas:, limit:, offset:)
          if filter_shas
            # When filtering by PRs, get check suites for those specific SHAs
            CheckSuite.where(repository_id: repository_id, head_sha: filter_shas)
              .includes(:creator)
              .order(:id)
              .limit(limit)
              .offset(offset)
              .to_a
          else
            # Get all check suites for the repository
            CheckSuite.where(repository_id: repository_id)
              .includes(:creator)
              .order(:id)
              .limit(limit)
              .offset(offset)
              .to_a
          end
        end

        def count_check_suites_for_repository(repository_id:, filter_shas:)
          if filter_shas
            CheckSuite.where(repository_id: repository_id, head_sha: filter_shas).count
          else
            CheckSuite.where(repository_id: repository_id).count
          end
        end

        def build_check_suite_hash(check_suite)
          {
            id: check_suite.id,
            resource_id: check_suite.id.to_s,
            repository_resource_id: check_suite.repository_id.to_s,
            head_sha: check_suite.head_sha,
            status: map_check_suite_status_to_protobuf_enum(check_suite.status),
            conclusion: map_check_suite_conclusion_to_protobuf_enum(check_suite.conclusion),
            creator_resource_id: check_suite.creator ? check_suite.creator.id.to_s : "",
            head_branch: check_suite.head_branch || "",
            url: check_suite.permalink || "",
            github_id: check_suite.id.to_s,
            creator_id: check_suite.creator_id&.to_s || "",
            created_at: { seconds: check_suite.created_at.to_i, nanos: 0 },
            updated_at: { seconds: check_suite.updated_at.to_i, nanos: 0 }
          }
        end

        def map_check_suite_status_to_protobuf_enum(status)
          case status&.to_s
          when "requested"
            :EXPORT_CHECK_SUITE_STATUS_REQUESTED
          when "in_progress"
            :EXPORT_CHECK_SUITE_STATUS_IN_PROGRESS
          when "completed"
            :EXPORT_CHECK_SUITE_STATUS_COMPLETED
          when "queued"
            :EXPORT_CHECK_SUITE_STATUS_QUEUED
          else
            :EXPORT_CHECK_SUITE_STATUS_INVALID
          end
        end

        def map_check_suite_conclusion_to_protobuf_enum(conclusion)
          case conclusion&.to_s
          when "success"
            :EXPORT_CHECK_SUITE_CONCLUSION_SUCCESS
          when "failure"
            :EXPORT_CHECK_SUITE_CONCLUSION_FAILURE
          when "neutral"
            :EXPORT_CHECK_SUITE_CONCLUSION_NEUTRAL
          when "cancelled"
            :EXPORT_CHECK_SUITE_CONCLUSION_CANCELLED
          when "skipped"
            :EXPORT_CHECK_SUITE_CONCLUSION_SKIPPED
          when "timed_out"
            :EXPORT_CHECK_SUITE_CONCLUSION_TIMED_OUT
          when "action_required"
            :EXPORT_CHECK_SUITE_CONCLUSION_ACTION_REQUIRED
          when "startup_failure"
            :EXPORT_CHECK_SUITE_CONCLUSION_STARTUP_FAILURE
          when "stale"
            :EXPORT_CHECK_SUITE_CONCLUSION_STALE
          else
            :EXPORT_CHECK_SUITE_CONCLUSION_INVALID
          end
        end

        def build_export_response(check_suites, total_count)
          MonolithTwirp::Elm::Actions::V1::ExportCheckSuitesResponse.new(
            success: true,
            export_check_suites: check_suites,
            total_count: total_count,
            error_message: ""
          )
        end
      end
    end
  end
end
