# typed: true
# frozen_string_literal: true

module Api::Internal::Twirp::ActionsResults
  module Core
    module V1
      class ListArtifacts
        attr_reader :req, :env

        LIST_ARTIFACTS_LIMIT = 1000

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

          params = {
            repository_id: repository.id,
            check_suite_id: check_suite.id,
          }

          params[:id] = req.id_filter.value if req.id_filter.present?
          params[:name] = req.name_filter.value if req.name_filter.present?

          artifacts = Artifact.where(**params).limit(LIST_ARTIFACTS_LIMIT)
          results_artifacts = artifacts.filter(&:not_expired?).filter(&:is_results_artifact?).map do |artifact|
            backend_ids = artifact.get_results_ids_from_source_url
            {
              workflow_run_backend_id: backend_ids[:workflow_run_backend_id],
              workflow_job_run_backend_id: backend_ids[:workflow_job_run_backend_id],
              database_id: artifact.id,
              name: artifact.name,
              size: artifact.size,
              created_at: Google::Protobuf::Timestamp.new(seconds: artifact.created_at.to_i),
            }
          end

          { artifacts: results_artifacts }
        end

        private

        def repository
          @repository ||= Repository.find_by(id: req.repository_id)
        end

        def check_suite
          @check_suite ||= CheckSuite.find_by(id: req.check_suite_id, repository_id: req.repository_id)
        end
      end
    end
  end
end
