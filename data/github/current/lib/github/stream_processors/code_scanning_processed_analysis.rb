# typed: true
# frozen_string_literal: true

# require 'securerandom' for UUID generation
require "securerandom"

module GitHub
  module StreamProcessors
    # Once Turboscan has completed the ingestion of an Analysis, it
    # signals on the ProcessedAnalysis topic.
    # We use this to synchronize the check annotations.
    class CodeScanningProcessedAnalysis < BaseProcessor
      include TransientErrorResiliency

      class Error < StandardError; end

      DEFAULT_GROUP_ID = "code_scanning_processed_analysis"
      DEFAULT_SUBSCRIBE_TO = [
        /code_scanning.v0.ProcessedAnalysis\Z/,
        /code_scanning.v0.FailedAnalysis\Z/,
      ].freeze

      # :min_bytes and :max_wait_time define how frequently we fetch a new batch,
      # and :max_bytes_per_partition defines the max size of a batch.
      # :session_timeout defines how long to wait before considering the consumer
      # non-responding.
      #
      # We currently say to fetch at new batch every 0.2 seconds or
      # if there are at least 5KB of data, and not to get more than 100 KB in a
      # batch. We promise to process the 100KB within 60 seconds.
      # Our messages here are pretty small (<1KB) so we claim that we can process
      # >100 messages in ~60 seconds.
      options[:min_bytes] = 5.kilobytes
      options[:max_wait_time] = 0.2.seconds
      options[:max_bytes_per_partition] = 100.kilobytes
      options[:session_timeout] = 60.seconds
      options[:start_from_beginning] = false

      resolve_tenant_context do |message|
        Repositories::Public.get_active_or_deleted!(message.value[:repository_id]).owner&.business
      end

      def setup(group_id: nil, subscribe_to: nil)
        options[:group_id] ||= DEFAULT_GROUP_ID
        options[:subscribe_to] ||= DEFAULT_SUBSCRIBE_TO
        self.transient_error_max_retries = 20
      end

      def process_message(message)
        analysis = message.value
        repo_id = analysis[:repository_id]
        repo = Repository.find_by(id: repo_id)

        if repo.present? && CodeScanning::ToolStatusMetricJob.should_perform?(repo: repo, ref: analysis[:ref])
          CodeScanning::ToolStatusMetricJob.perform_later(repository_id: repo.id, ref: analysis[:ref])
        end

        if message.topic.ends_with?("FailedAnalysis")
          GitHub.dogstats.increment("github/code_scanning.slo", tags: ["name:availability/analysis-processing", "success:false"])
          return
        elsif message.topic.ends_with?("ProcessedAnalysis")
          GitHub.dogstats.increment("github/code_scanning.slo", tags: ["name:availability/analysis-processing", "success:true"])
        end
        analyzed_commit_oid = analysis[:commit_oid]

        @current_error_context.merge!(repo_id: repo_id, analyzed_commit_oid: analyzed_commit_oid)
        GitHub.logger.info(
          "Received new processed analysis message",
          "code.namespace" => "CodeScanningProcessedAnalysis",
          "code.function" => "process_message",
          "gh.repo.id" => repo_id,
          "git.commit.oid" => analyzed_commit_oid,
        )

        # The repository has been deleted, return early
        return if repo.nil?

        annotated_commit_oid = analyzed_commit_oid
        ref = analysis[:ref]

        pr_merge_ref_matcher = ref&.match(/\Arefs\/pull\/[0-9]+\/merge\Z/)
        if pr_merge_ref_matcher
          analyzed_commit = repo.commits.find(analyzed_commit_oid)
          if analyzed_commit.nil?
            GitHub.logger.info(
              "Analyzed commit not found. It may have been garbage collected.",
              "code.namespace" => "CodeScanningProcessedAnalysis",
              "code.function" => "process_message",
              "gh.repo.id" => repo_id,
              "git.commit.oid" => analyzed_commit_oid,
            )
            return
          end
          # If the analysis is for a pull request merge commit, the check run we need to update will actually have been posted to the head of the pull request.
          annotated_commit_oid = analyzed_commit.parent_oids[1]
        end
        @current_error_context[:annotated_commit_oid] = annotated_commit_oid

        check_run_ids = analysis[:check_run_ids]
        tools = analysis[:tools]
        check_runs = T.let([], T::Array[CheckRun])
        if check_run_ids.present?
          if tools.present?
            with_primaries ApplicationRecord::RepositoriesActionsChecks do
              check_runs = CheckRun.align_checkruns_with_tools(
                check_run_ids: check_run_ids,
                tools: tools,
                repository: repo,
                annotated_commit_oid: annotated_commit_oid,
                analyzed_commit_oid: analyzed_commit_oid,
                ref: ref
              )
            end
          else
            # Something went wrong in the processing, mark the checkrun as neutral
            with_primaries ApplicationRecord::RepositoriesActionsChecks do
              check_runs = CheckRun.where(repository_id: repo_id, id: check_run_ids).load
              check_runs.each do |check_run|
                check_run.conclusion = "neutral"
                # TODO: This could be the processing error from TS, or we could include that in the summary body.
                check_run.title = "Error when processing the SARIF file"
                check_run.save
              end
              # Since the ingestion failed, we do not want to try and performa a Diff, so we can return early.
              return
            end
          end
        else
          if tools.present?
            # If we have no check runs then probably the upload was for a branch, not a PR, and no pull request for the
            # branch existed when the analysis was uploaded. However, a PR could have been created since then. We have a
            # PR-creation listener that is meant to create the suites and check runs for existing analyses, but it would
            # not have been able to find the analysis that was still being processed. So we need to check here again.
            # Note that this logic is duplicated in the RepositoryCodeScanningUploadAPI controller to
            # guard against race conditions. If you change it here it should also be updated there.
            if analysis[:ref].starts_with?("refs/heads/")
              pull_request = with_primaries ApplicationRecord::IssuesPullRequests do
                PullRequest.find_open_based_on_head_ref(repo.id, analysis[:ref])&.find { |pr| pr.repository_id == repo.id && !pr.spammy? }
              end

              # This check might be overkill but let's ensure that the analysis is for the right sha
              is_head_analysis = analysis[:commit_oid] == pull_request&.head_sha

              if pull_request.present? && is_head_analysis && pull_request.base_ref != analysis[:ref].delete_prefix("refs/heads/")
                with_primaries ApplicationRecord::RepositoriesActionsChecks do
                  code_scanning_check_suite = CheckRun.create_code_scanning_check_suite(
                    repository: repo,
                    annotated_commit_oid: analysis[:commit_oid],
                    analyzed_commit_oid: analysis[:commit_oid],
                    ref: analysis[:ref],
                    base_ref: "refs/heads/#{pull_request.base_ref}",
                    base_sha: pull_request.base_sha,
                    )

                  check_runs = CheckRun.create_code_scanning_check_runs(
                    check_suite: code_scanning_check_suite.check_suite,
                    tool_names: tools.map { |t| t[:name] },
                    )
                end
              end
            end
          end
        end

        with_primaries ApplicationRecord::RepositoriesActionsChecks, ApplicationRecord::Notify do
          repo.refresh_code_scanning_status(
            check_run_ids: check_runs.map(&:id),
            refresh_reason: :processed_analysis)
        end
      end
    end
  end
end
