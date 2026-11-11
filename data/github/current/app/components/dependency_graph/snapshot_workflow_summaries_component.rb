# typed: true
# frozen_string_literal: true

module DependencyGraph
  class SnapshotWorkflowSummariesComponent < ApplicationComponent
    # @param repository [Repository]
    # @param owner [User, Organization]
    # @param workflow_runs [Array<Actions::WorkflowRun>]
    # @param overflow_count [Integer] Number of additional failures beyond the displayed set.
    # @param workflow_page_url [String] URL to the overall Dependency Graph workflow page.
    def initialize(repository:, owner:, workflow_runs:, overflow_count:, workflow_page_url:)
      @repository = repository
      @owner = owner
      @workflow_runs = workflow_runs
      @overflow_count = overflow_count
      @workflow_page_url = workflow_page_url
      @summaries_cache = {}
    end

    def render?
      @workflow_runs.any?
    end

    def workflow_runs
      @workflow_runs
    end

    def overflow_count
      @overflow_count
    end

    def overflow?
      @overflow_count > 0
    end

    def workflow_page_url
      @workflow_page_url
    end

    def run_title(workflow_run)
      workflow_run.name.presence || workflow_run.workflow_name
    end

    def run_url(workflow_run)
      Rails.application.routes.url_helpers.workflow_run_path(@owner, @repository, workflow_run_id: workflow_run.id)
    end

    def run_job_url(workflow_run)
      job = workflow_run.latest_workflow_run_job
      return nil unless job

      Rails.application.routes.url_helpers.workflow_run_job_path(@owner, @repository, workflow_run_id: workflow_run.id, job_id: job.id)
    end

    def run_summary_html(workflow_run)
      job_summary = cached_summary(workflow_run)
      return GitHub::HTMLSafeString::EMPTY unless job_summary

      rendered_steps = job_summary.step_summaries.filter_map do |step|
        next if step[:content].blank?

        helpers.github_simplified_markdown(step[:content])
      end

      rendered_steps.any? ? helpers.safe_join(rendered_steps) : GitHub::HTMLSafeString::EMPTY
    end

    def run_summary_blank?(workflow_run)
      job_summary = cached_summary(workflow_run)
      job_summary.nil? || job_summary.step_summaries.all? { |s| s[:content].blank? }
    end

    private

    def cached_summary(workflow_run)
      return @summaries_cache[workflow_run.id] if @summaries_cache.key?(workflow_run.id)

      @summaries_cache[workflow_run.id] = workflow_run.latest_workflow_run_job&.get_summary
    end
  end
end
