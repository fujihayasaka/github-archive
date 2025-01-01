# typed: true
# frozen_string_literal: true

module Api::Internal::Twirp::Actions
  module Core
    module V1
      class UpdateWorkflowRun
        include GitHub::Memoizer

        attr_reader :req

        def self.call(request)
          new(request).call
        end

        def initialize(request)
          @req = request
        end

        def call
          return Twirp::Error.invalid_argument("missing repository_id", argument: "repository_id") if req.repository_id.blank?
          return Twirp::Error.invalid_argument("missing run_name", argument: "run_name") if req.run_name.blank?
          return Twirp::Error.not_found("repository does not exist", argument: "repository_id") unless repository

          begin
            ActiveRecord::Base.connected_to(role: :writing) do
              # To avoid replication lag we are reading from the primary here because
              # we often update the record immediately after creating it.
              return Twirp::Error.not_found("workflow_run does not exist", argument: "workflow_run_id") unless workflow_run

              workflow_run.update!(name: req.run_name, explicit_name: true)
            end
          rescue ActiveRecord::RecordInvalid => e
            return Twirp::Error.internal("failed to update workflow run name: #{e.message}")
          end

          {}
        end

        memoize def repository
          type, id = Platform::Helpers::NodeIdentification.from_global_id(req.repository_id.global_id)
          Repositories.domain.by_id(id.to_i) if type == "Repository"
        end

        memoize def workflow_run
          repository.workflow_runs.find_by_id(req.workflow_run_id)
        end
      end
    end
  end
end
