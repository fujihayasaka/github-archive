# typed: true
# frozen_string_literal: true

module Actions
  module WorkflowRuns
    class AgenticWorkflowFileComponent < ApplicationComponent
      attr_reader :check_suite, :current_repository, :commit, :annotations, :agentic_workflow_file_path

      def initialize(check_suite:, current_repository:, commit:, annotations:, agentic_workflow_file_path:)
        @check_suite = check_suite
        @workflow_run = check_suite.workflow_run
        @current_repository = current_repository
        @commit = commit
        @annotations = annotations
        @agentic_workflow_file_path = agentic_workflow_file_path
        @required_workflow_source_repo = if required_workflow_execution?
          if FeatureFlag.vexi.enabled?(:repos_by_id_components, default: false)
            Repositories.domain.by_id(@workflow_run.imposer_repository_id)
          else
            Repository.find_by(id: @workflow_run.imposer_repository_id)
          end
        end
      end

      def agentic_workflow_file_blob_path(path)
        return unless path.present?
        return blob_path(path, @commit.oid, @current_repository) unless required_workflow_execution?

        blob_path(path, @workflow_run.workflow_file_checkout_sha, @required_workflow_source_repo) unless @required_workflow_source_repo.nil?
      end

      def agentic_workflow_file_commit_path(path)
        return unless path.present?
        return commit_path(commit.oid) unless required_workflow_execution?

        commit_path(@workflow_run.workflow_file_checkout_sha, @required_workflow_source_repo) unless @required_workflow_source_repo.nil?
      end

      def agentic_workflow_file_commit_oid(path)
        return unless path.present?
        return commit.abbreviated_oid unless required_workflow_execution?

        return if @required_workflow_source_repo.nil?

        begin
          commit = Repositories.domain.commits.by_oid(
            repository: @required_workflow_source_repo,
            commit_oid: @workflow_run.workflow_file_checkout_sha
          )
          commit&.abbreviated_oid
        rescue GitRPC::ObjectMissing
          nil
        end
      end

      def agentic_workflow_file_blob(path)
        return unless path.present?
        return @current_repository.blob(@commit.oid, path) unless required_workflow_execution?

        begin
          @required_workflow_source_repo.blob(@workflow_run.workflow_file_checkout_sha, path) unless @required_workflow_source_repo.nil?
        rescue GitRPC::ObjectMissing
          nil
        end
      end

      def agentic_workflow_file_path_display_name(path)
        return unless path.present?
        return path unless required_workflow_execution?

        [@required_workflow_source_repo.name_with_display_owner, path].join("/") unless @required_workflow_source_repo.nil?
      end

      def required_workflow_execution?
        @workflow_run.required_workflow_run?
      end
    end
  end
end
