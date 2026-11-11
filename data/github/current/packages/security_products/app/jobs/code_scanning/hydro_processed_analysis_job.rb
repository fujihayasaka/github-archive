# typed: strict
# frozen_string_literal: true

# Once Turboscan has completed the ingestion of an Analysis, it
# signals on the ProcessedAnalysis topic.
# We use this to synchronize the check annotations.
class CodeScanning::HydroProcessedAnalysisJob < Repositories::RepositoryHydroMessageJob
  retry_on_dirty_exit

  queue_as :hydro_code_scanning_processed_analysis

  sig { void }
  def perform
    return unless FeatureFlag.vexi.enabled?(:hydro_code_scanning_processed_analysis_job, repository, repository.owner, default: false)

    analysis = message

    if ::CodeScanning::ToolStatusMetricJob.should_perform?(repo: repository, ref: analysis[:ref])
      ::CodeScanning::ToolStatusMetricJob.perform_later(repository_id: repository.id, ref: analysis[:ref])
    end

    if topic.ends_with?("FailedAnalysis")
      GitHub.dogstats.increment("github/code_scanning.slo", tags: ["name:availability/analysis-processing", "success:false"])
      return
    elsif topic.ends_with?("ProcessedAnalysis")
      GitHub.dogstats.increment("github/code_scanning.slo", tags: ["name:availability/analysis-processing", "success:true"])
    end
    analyzed_commit_oid = analysis[:commit_oid]

    Failbot.push("git.commit.oid": analyzed_commit_oid)
    GitHub.logger.info(
      "Received new processed analysis message",
      "code.namespace" => "CodeScanningProcessedAnalysis",
      "code.function" => "process_message",
      "gh.repo.id" => repository.id,
      "git.commit.oid" => analyzed_commit_oid,
    )

    # The repository has been deleted, return early
    return if repository.deleted?

    annotated_commit_oid = analyzed_commit_oid
    ref = analysis[:ref]

    pr_merge_ref_matcher = ref&.match(/\Arefs\/pull\/[0-9]+\/merge\Z/)
    if pr_merge_ref_matcher
      analyzed_commit = repository.commits.find(analyzed_commit_oid)
      if analyzed_commit.nil?
        GitHub.logger.info(
          "Analyzed commit not found. It may have been garbage collected.",
          "code.namespace" => "CodeScanningProcessedAnalysis",
          "code.function" => "process_message",
          "gh.repo.id" => repository.id,
          "git.commit.oid" => analyzed_commit_oid,
        )
        return
      end
      # If the analysis is for a pull request merge commit, the check run we need to update will actually have been posted to the head of the pull request.
      annotated_commit_oid = analyzed_commit.parent_oids[1]
    end
    Failbot.push(annotated_commit_oid: annotated_commit_oid)

    check_run_ids = analysis[:check_run_ids]
    tools = analysis[:tools]
    check_runs = T.let([], T::Array[CheckRun])
    if check_run_ids.present?
      if tools.present?
        with_primaries [ApplicationRecord::RepositoriesActionsChecks] do
          check_runs = CheckRun.align_checkruns_with_tools(
            check_run_ids: check_run_ids,
            tools: tools,
            repository: repository,
            annotated_commit_oid: annotated_commit_oid,
            analyzed_commit_oid: analyzed_commit_oid,
            ref: ref
          )
        end
      else
        # Something went wrong in the processing, mark the checkrun as neutral
        with_primaries [ApplicationRecord::RepositoriesActionsChecks] do
          check_runs = CheckRun.where(repository_id: repository.id, id: check_run_ids).load
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
          pull_request = with_primaries [ApplicationRecord::IssuesPullRequests] do
            PullRequest.find_open_based_on_head_ref(repository.id, analysis[:ref])&.find { |pr| pr.repository_id == repository.id && !pr.spammy? }
          end

          # This check might be overkill but let's ensure that the analysis is for the right sha
          is_head_analysis = analysis[:commit_oid] == pull_request&.head_sha

          if pull_request.present? && is_head_analysis && pull_request.base_ref != analysis[:ref].delete_prefix("refs/heads/")
            with_primaries [ApplicationRecord::RepositoriesActionsChecks] do
              code_scanning_check_suite = CheckRun.create_code_scanning_check_suite(
                repository: repository,
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

    with_primaries [ApplicationRecord::RepositoriesActionsChecks, ApplicationRecord::Notify] do
      repository.refresh_code_scanning_status(
        check_run_ids: check_runs.map(&:id),
        refresh_reason: :processed_analysis)
    end
  end
end
