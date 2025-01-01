# typed: true
# frozen_string_literal: true

require "monolith-twirp-elm-actions"

module Api::Internal::Twirp::Elm
  module Actions
    module V1
      # Handler for the MonolithTwirp::Elm::Actions::V1::ExportCheckRunsAPIService
      class ExportCheckRunsAPIHandler < Api::Internal::Twirp::Handler

        DEFAULT_PER_PAGE = 30 # Default number of items per page for pagination
        PR_BATCH_MULTIPLIER = 5 # How many times larger the PR batch should be compared to the requested page size to ensure we get enough PRs for filtering
        MAX_PR_BATCH_SIZE = 1000 # Maximum size of the PR batch to avoid excessive memory usage

        allow_access_for :client, allowed_clients: %w[elm migrations_vnext]
        handles_service MonolithTwirp::Elm::Actions::V1::ExportCheckRunsAPIService

        # Public: Implementation of the ExportCheckRuns Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Elm::Actions::V1::ExportCheckRunsRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response either as a
        # MonolithTwirp::Elm::Actions::V1::ExportCheckRunsResponse, or a Twirp::Error.
        sig do
          params(
            req: MonolithTwirp::Elm::Actions::V1::ExportCheckRunsRequest,
            env: T::Hash[String, T.untyped]
          ).returns(T.any(MonolithTwirp::Elm::Actions::V1::ExportCheckRunsResponse, Twirp::Error))
        end
        def export_check_runs(req, env)
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
            # If no PRs exist, we want to return all check runs, not none
            pr_head_shas.any? ? pr_head_shas : nil
          end

          # Calculate offset for the current page
          offset = (page - 1) * per_page

          # Get check runs for the current page using domain method
          check_runs = get_check_runs_for_repository(
            repository_id: repo_id,
            filter_shas: filter_shas,
            limit: per_page,
            offset: offset
          )

          # Get total count for pagination metadata
          total_count = count_check_runs_for_repository(
            repository_id: repo_id,
            filter_shas: filter_shas
          )

          export_check_runs = check_runs.map do |check_run|
            build_check_run_hash(check_run)
          end

          build_export_response(export_check_runs, total_count)
        rescue StandardError => e # rubocop:disable Lint/RescueException
          GitHub.logger.error("Failed to export check runs for repository #{repo_id}: #{e.message}")
          GitHub.logger.error(T.must(e.backtrace).join("\n")) if e.backtrace

          Twirp::Error.internal("Failed to export check runs").tap do |error|
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

        def get_check_runs_for_repository(repository_id:, filter_shas:, limit:, offset:)
          if filter_shas
            # When filtering by PRs, get check runs for those specific SHAs
            check_suite_ids = CheckSuite.where(repository_id: repository_id, head_sha: filter_shas).pluck(:id)
            return [] if check_suite_ids.empty?

            # Get check runs for those check suites with pagination
            CheckRun.joins(:check_suite)
              .where(repository_id: repository_id, check_suite_id: check_suite_ids)
              .includes(:check_suite, :creator, :repository)
              .order(:id)
              .limit(limit)
              .offset(offset)
              .to_a
          else
            # Get all check runs for the repository
            CheckRun.where(repository_id: repository_id)
              .includes(:check_suite, :creator, :repository)
              .order(:id)
              .limit(limit)
              .offset(offset)
              .to_a
          end
        end

        def count_check_runs_for_repository(repository_id:, filter_shas:)
          if filter_shas
            check_suite_ids = CheckSuite.where(repository_id: repository_id, head_sha: filter_shas).pluck(:id)
            return 0 if check_suite_ids.empty?

            CheckRun.where(repository_id: repository_id, check_suite_id: check_suite_ids).count
          else
            CheckRun.where(repository_id: repository_id).count
          end
        end

        def build_check_run_hash(check_run)
          # Safely access status and conclusion attributes
          status_value = check_run.try(:status) || "completed"
          conclusion_value = check_run.try(:conclusion) || "success"

          {
            id: check_run.id,
            resource_id: check_run.id.to_s,
            repository_resource_id: check_run.repository_id.to_s,
            name: check_run.name,
            head_sha: check_run.check_suite&.head_sha || "",
            status: map_check_run_status_to_protobuf_enum(status_value),
            conclusion: map_check_run_conclusion_to_protobuf_enum(conclusion_value),
            check_suite_resource_id: check_run.check_suite_id.to_s,
            creator_resource_id: check_run.creator_id.to_s,
            details_url: check_run.details_url || "",
            html_url: check_run.respond_to?(:permalink) ? check_run.permalink : "",
            external_id: check_run.external_id || "",
            summary: "",
            text: "",
            github_id: check_run.id.to_s,
            creator_id: check_run.creator_id.to_s,
            created_at: { seconds: check_run.created_at.to_i, nanos: 0 },
            updated_at: { seconds: check_run.updated_at.to_i, nanos: 0 },
            started_at: check_run.started_at ? { seconds: check_run.started_at.to_i, nanos: 0 } : nil,
            completed_at: check_run.completed_at ? { seconds: check_run.completed_at.to_i, nanos: 0 } : nil
          }
        end

        def map_check_run_status_to_protobuf_enum(status)
          status_str = status.to_s

          if status_str == "queued"
            :EXPORT_CHECK_RUN_STATUS_QUEUED
          elsif status_str == "in_progress"
            :EXPORT_CHECK_RUN_STATUS_IN_PROGRESS
          elsif status_str == "completed"
            :EXPORT_CHECK_RUN_STATUS_COMPLETED
          else
            :EXPORT_CHECK_RUN_STATUS_INVALID
          end
        end

        def map_check_run_conclusion_to_protobuf_enum(conclusion)
          return :EXPORT_CHECK_RUN_CONCLUSION_UNSPECIFIED if conclusion.nil?

          conclusion_str = conclusion.to_s

          if conclusion_str == "success"
            :EXPORT_CHECK_RUN_CONCLUSION_SUCCESS
          elsif conclusion_str == "failure"
            :EXPORT_CHECK_RUN_CONCLUSION_FAILURE
          elsif conclusion_str == "neutral"
            :EXPORT_CHECK_RUN_CONCLUSION_NEUTRAL
          elsif conclusion_str == "cancelled"
            :EXPORT_CHECK_RUN_CONCLUSION_CANCELLED
          elsif conclusion_str == "skipped"
            :EXPORT_CHECK_RUN_CONCLUSION_SKIPPED
          elsif conclusion_str == "timed_out"
            :EXPORT_CHECK_RUN_CONCLUSION_TIMED_OUT
          elsif conclusion_str == "action_required"
            :EXPORT_CHECK_RUN_CONCLUSION_ACTION_REQUIRED
          else
            :EXPORT_CHECK_RUN_CONCLUSION_UNSPECIFIED
          end
        end

        def build_export_response(check_runs, total_count)
          MonolithTwirp::Elm::Actions::V1::ExportCheckRunsResponse.new(
            success: true,
            export_check_runs: check_runs,
            total_count: total_count,
            error_message: ""
          )
        end
      end
    end
  end
end
