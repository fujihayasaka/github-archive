# typed: true
# frozen_string_literal: true

module Api::Internal::Twirp::ActionsResults
  module Core
    module V1
      class GetWorkflowRunExecution
        attr_reader :req, :env

        def self.call(request, env)
          new(request, env).call
        end

        def initialize(request, env)
          @req = request
          @env = env
        end

        def call
          return Twirp::Error.not_found("repository does not exist", argument: "repository_id") unless repository
          return Twirp::Error.not_found("check suite does not exist", argument: "check_suite_id") unless check_suite
          return Twirp::Error.not_found("execution does not exist", argument: "workflow_run_backend_id") unless execution

          {
            repository_id: repository.id,
            check_suite_id: check_suite.id,
            workflow_run_id: execution.workflow_run_id,
            workflow_run_execution_id: execution.id,
            attempt: execution.attempt,
            status: ActionsResults::Utils.to_results_status(execution.status),
            conclusion: ActionsResults::Utils.to_results_conclusion(execution.conclusion),
            started_at: execution.started_at ? Google::Protobuf::Timestamp.new(seconds: execution.started_at.to_i) : nil,
            completed_at: execution.completed_at ? Google::Protobuf::Timestamp.new(seconds: execution.completed_at.to_i) : nil,
            run_stamp_url: execution.run_stamp_url,
          }
        end

        private

        def check_suite
          @check_suite ||= CheckSuite.find_by(id: req.check_suite_id)
        end

        def repository
          @repository ||= Repository.find_by(id: req.repository_id)
        end

        def execution
          @exeuction ||= check_suite.workflow_run.workflow_run_executions.find_by(external_id: req.workflow_run_backend_id)
        end
      end
    end
  end
end
