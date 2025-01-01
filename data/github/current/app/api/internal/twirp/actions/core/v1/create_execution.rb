# typed: true
# frozen_string_literal: true

module Api::Internal::Twirp::Actions
  module Core
    module V1
      class CreateExecution
        attr_reader :req

        def self.call(request)
          new(request).call
        end

        def initialize(request)
          @req = request
        end

        def call
          return Twirp::Error.not_found("repository does not exist", argument: "repository_id") unless repository
          return Twirp::Error.not_found("workflow_run does not exist", argument: "workflow_run_id") unless workflow_run
          return Twirp::Error.not_found("actor does not exist", argument: "actor_id") if req.actor_id.present? && !actor
          return Twirp::Error.invalid_argument("missing plan_id", argument: "plan_id") if plan_id.blank?
          return Twirp::Error.invalid_argument("attempt must be > 0", argument: "attempt") if attempt < 1

          ActiveRecord::Base.connected_to(role: :writing) do
            workflow_run.create_new_workflow_execution(
              external_id: plan_id,
              attempt: attempt,
              actor: actor,
              execution_graph: execution_graph,
              # launch returns "" when there is an error or no referenced workflows, but we want NULL in the database in these cases
              referenced_workflows: referenced_workflows.blank? ? nil : referenced_workflows,
            )
          end

          {}
        end

        def repository
          return @repository if @repository

          id = Platform::Helpers::NodeIdentification.from_global_id(req.repository_id.global_id).last
          @repository = Repository.find_by(id: id)
        end

        def workflow_run
          return @workflow_run if @workflow_run

          @workflow_run = repository.workflow_runs.find_by_id(req.workflow_run_id)
        end

        def plan_id
          req.plan_id
        end

        def attempt
          req.attempt
        end

        def actor
          return nil unless req.actor_id.present?
          return @actor if @actor_id

          id = Platform::Helpers::NodeIdentification.from_global_id(req.actor_id.global_id).last
          @actor = User.find_by(id: id)
        end

        def execution_graph
          req.execution_graph
        end

        def referenced_workflows
          req.referenced_workflows
        end
      end
    end
  end
end
