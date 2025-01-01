# typed: true
# frozen_string_literal: true

module Actions
  module WorkflowRuns
    class RerunDialogComponent < ApplicationComponent
      DEFAULT_VARIANT = :all_jobs
      VARIANTS = [DEFAULT_VARIANT, :failed_jobs, :single_job].freeze

      # job is required for `single_job` variant
      def initialize(
        current_repository:,
        workflow_run:,
        variant: DEFAULT_VARIANT,
        job: nil,
        dialog_id:
      )
        @current_repository = current_repository
        @workflow_run = workflow_run
        @variant = variant
        @job = job
        @dialog_id = dialog_id
      end

      def render?
        return false if @variant == :single_job && @job.blank?
        VARIANTS.include?(@variant)
      end

      def title
        case @variant
        when :failed_jobs
          "Re-run failed jobs"
        when :single_job
          "Re-run single job"
        else
          "Re-run all jobs"
        end
      end

      def subtitle
        parts = []
        parts << "A new attempt of this workflow will be started, including "
        parts << content_tag(:strong, job_description)
        if include_dependents_text?
          parts << " and dependents"
        end
        parts << ":"
        safe_join(parts)
      end

      def job_description
        case @variant
        when :failed_jobs
          "all failed jobs"
        when :single_job
          @job.check_run.visible_name
        else
          "all the jobs"
        end
      end

      def include_dependents_text?
        @variant != :all_jobs
      end

      def job_list_src
        case @variant
        when :failed_jobs
          workflow_run_failed_jobs_path(user_id: @current_repository.owner, repository: @current_repository, workflow_run_id: @workflow_run.id)
        when :single_job
          workflow_run_job_downstream_list_path(user_id: @current_repository.owner, repository: @current_repository, workflow_run_id: @workflow_run.id, job_id: @job.id)
        else
          workflow_run_jobs_list_path(user_id: @current_repository.owner, repository: @current_repository, workflow_run_id: @workflow_run.id)
        end
      end
    end
  end
end
