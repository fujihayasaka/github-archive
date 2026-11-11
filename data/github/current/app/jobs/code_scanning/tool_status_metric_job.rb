# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

# CodeScanning::ToolStatusMetricJob emits the tool status for every tool to Hydro.
# We use this to power a Kusto analytics dashboard (see https://github.com/github/code-scanning#code-and-config-we-own).
# This job is not critical to the functioning of Code Scanning
class CodeScanning::ToolStatusMetricJob < ApplicationJob
  queue_as :code_scanning

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  locked_by timeout: 1.hour, key: ->(job) {
    args, = job.arguments
    "#{ args[:repository_id] }-#{ args[:ref] }"
  }

  def self.should_perform?(repo:, ref:)
    !GitHub.enterprise? &&
    !FeatureFlag.vexi.enabled_or_raise?(:code_scanning_tool_status_processed_analysis_hydro_block, repo) && # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
    !FeatureFlag.vexi.enabled_or_raise?(:code_scanning_tool_status_processed_analysis_hydro_block, repo&.owner) && # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
    ref == "refs/heads/#{repo.default_branch}"
  end

  def perform(ref:, repository_id:)
    repo = if FeatureFlag.vexi.enabled?(:repos_by_id_jobs, default: false)
      T.cast(Repositories.domain.by_id(repository_id), T.nilable(Repository)) # rubocop:todo GitHub/AvoidCast
    else
      Repository.find_by(id: repository_id)
    end
    return if repo.nil?
    return if ref.blank?

    begin
      response = GitHub::Turboscan.get_tool_status(
        repository_id: repo.id,
        ref: ref,
      )
    rescue Faraday::Error, Faraday::TimeoutError => e
      # Sending the tool status info to Hydro isn't critical
      # so don't fail the job on error, just log it.
      GitHub.logger.error("Error fetching tool status from Turboscan",
        exception: e,
        "gh.repo.id": repo.id,
        "gh.git.ref": ref,
      )
      return
    end

    if response.nil? || response.data.nil? || response.error.present?
      GitHub.logger.error("No response when fetching tool status from Turboscan",
        error: response&.error,
        "gh.repo.id": repo.id,
        "gh.git.ref": ref,
      )
      return
    end

    tools = T.must(response.data).tools

    if tools.size > 50
      GitHub.logger.error("Refusing to emit tool status for #{tools.size} tools")
      return
    end

    workflows = CodeScanning::Status.fetch_workflows(repo, CodeScanning::Status.workflow_paths(tools))
    messages = CodeScanning::Status.messages(repo, tools, workflows)
    tools.each do |tool|
      CodeScanning::Status.emit_tool_status_hydro_event("processed_analysis", T.must(repo.id), ref, tool, messages)
    end
  end
end
