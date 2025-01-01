# typed: true
# frozen_string_literal: true

module Api::Internal::Twirp::Actions
  module Core
    module V1
      class GetWorkflowRunExecution
        include Api::Internal::Twirp::Actions::Core::V1::ArgumentsDependency
        include GitHub::Memoizer

        attr_reader :req, :env

        def self.call(req, env)
          new(req, env).call
        end

        def initialize(request, env)
          @req = request
          @env = env
        end

        def call
          return Twirp::Error.not_found("check suite does not exist", argument: "check_suite_global_id") unless check_suite
          return Twirp::Error.not_found("execution does not exist", argument: "workflow_run_execution_external_id") unless execution

          {
            referenced_workflows: execution.referenced_workflows
          }
        end

        private

        memoize def check_suite
          type, id = Platform::Helpers::NodeIdentification.from_global_id(req.check_suite_global_id&.global_id)
          return nil if type != "CheckSuite"
          CheckSuite.find_by(id: id)
        end

        def execution
          return nil if check_suite.workflow_run.nil?
          @execution ||= check_suite.workflow_run.workflow_run_executions.with_referenced_workflows.find_by(external_id: req.workflow_run_execution_external_id)
        end
      end
    end
  end
end
