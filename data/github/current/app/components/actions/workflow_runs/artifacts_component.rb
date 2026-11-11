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
            # Results artifacts are tied to a specific run execution, so we scope
            # by backend execution id to avoid cross-attempt leakage in the UI.
            artifact.workflow_run_backend_id == @execution.external_id
          else
            # Legacy artifacts are run-level and should only appear on latest
            # executions to match historical Actions UI behavior.
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

      def supports_file_browsing?(artifact)
        # Browse is intentionally constrained to signed/active results artifacts
        # and actor-level feature flag rollout to reduce blast radius.
        return false if artifact.expired?
        return false unless artifact.is_results_artifact?
        return false unless current_user

        FeatureFlag.vexi.enabled?("actions_artifact_file_browsing", current_user, current_repository, current_repository.owner, default: false)
      end
    end
  end
end
