# typed: true
# frozen_string_literal: true

module Api::Internal::Twirp::Actions
  module Core
    module V1
      class GetWorkflowRun
        include Api::Internal::Twirp::Actions::Core::V1::ActorsDependency
        include Api::Internal::Twirp::Actions::Core::V1::ArgumentsDependency

        attr_reader :req

        def self.call(req)
          new(req).call
        end

        def initialize(request)
          @req = request
        end

        def call
          return Twirp::Error.invalid_argument("must be non-empty", argument: "workflow_run_id") if req.workflow_run_id.blank?

          unless workflow_run = Actions::WorkflowRun.find_by(id: req.workflow_run_id)
            return Twirp::Error.not_found("workflow run does not exist", argument: "workflow_run_id")
          end

          {
            workflow_file_path: workflow_run.workflow_file_path,
            repository_id: workflow_run.repository_id,
            required_workflow_checkout_sha: workflow_run.workflow_file_checkout_sha
          }
        end
      end
    end
  end
end
