# typed: true
# frozen_string_literal: true

module Api::Internal::Twirp::ActionsResults
  module Core
    module V1
      class DeleteArtifactFromMonolith
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
          return Twirp::Error.invalid_argument("must specify an artifact name", argument: "name") if artifact_name.empty?

          artifact = Artifact.find_by(
            repository_id: repository.id,
            check_suite_id: check_suite.id,
            name: artifact_name
          )

          return Twirp::Error.not_found("artifact does not exist", argument: "name") unless artifact

          artifact.destroy

          { ok: true, artifact_id: artifact.id }
        end

        private

        def repository
          @repository ||= if GitHub.flipper[:repos_domain_twirp].enabled?
            Repositories.domain.by_id(req.repository_id)
          else
            Repository.find_by(id: req.repository_id)
          end
        end

        def check_suite
          @check_suite ||= CheckSuite.find_by(id: req.check_suite_id, repository_id: req.repository_id)
        end

        def artifact_name
          req.name || ""
        end
      end
    end
  end
end
