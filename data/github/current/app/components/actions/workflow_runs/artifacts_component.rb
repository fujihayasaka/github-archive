# typed: true
# frozen_string_literal: true

module Actions
  module WorkflowRuns
    class ArtifactsComponent < ApplicationComponent
      attr_reader :check_suite, :current_repository, :artifacts

      def initialize(check_suite:, current_repository:, execution: nil)
        @check_suite = check_suite
        @current_repository = current_repository
        @execution = execution || check_suite.workflow_run.latest_workflow_run_execution
        @artifacts = artifacts_filtered_by_execution
      end

      def render?
        @artifacts.any?
      end

      def artifacts_filtered_by_execution
        artifacts = check_suite.artifacts.order(:name).limit(Artifact::MAX_READ_LIMIT).to_a

        artifacts.filter do |artifact|
          if artifact.is_results_artifact?
            # filter results artifacts by their execution's plan id
            artifact.workflow_run_backend_id == @execution.external_id
          else
            # only show non-results artifacts on latest executions
            @execution.is_latest_execution?
          end
        end
      end

      def channels
        channels = if @execution.present?
          [@check_suite.workflow_run.execution_channel, @check_suite.workflow_run.artifacts_channel]
        else
          [check_suite.workflow_run.artifacts_channel]
        end
      end

      def show_digest?
        !GitHub.enterprise? && @current_repository.feature_enabled?(:actions_artifacts_digest_ui)
      end
    end
  end
end
