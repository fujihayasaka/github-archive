# typed: true
# frozen_string_literal: true

module Actions
  module WorkflowRuns
    class JobSummaryContentComponent < ApplicationComponent
      DOCS_URL = "https://docs.github.com/actions/using-workflows/workflow-commands-for-github-actions#adding-a-job-summary"

      def initialize(check_suite:, workflow_job_run:, preload: false)
        @check_suite = check_suite
        @workflow_job_run = workflow_job_run
        @preload = preload
        @show_error = false
      end

      def job_summary
        @job_summary ||= @workflow_job_run.get_summary

        # if we get an invalid or failed response
        if @job_summary.nil?
          GitHub.dogstats.increment("actions.job_summary_component.error", tags: ["method:job_summary"])
          @show_error = true
        end

        @job_summary
      end

      # Job summaries have the same retention policy as logs so the same expiration logic can be used
      def expired?
        @workflow_job_run.check_run.expired_logs?
      end

      def rendered_steps
        return @rendered_steps if defined?(@rendered_steps)
        return [] unless job_summary

        @rendered_steps = job_summary&.step_summaries&.map do |step_summary|
          # render steps separately to avoid markdown errors affecting other steps in the job summary
          GitHub::Goomba::MarkdownPipeline.to_html(step_summary[:content], { check_suite: @check_suite }, nil)
        end || []
      rescue NameError => e
        # worst case scenario if a change happens in the markdown pipeline that breaks the rendering
        GitHub.dogstats.increment("actions.job_summary_component.error", tags: ["method:rendered_steps"])
        Failbot.report(e)
        @show_error = true

        []
      end
    end
  end
end
