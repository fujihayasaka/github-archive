# typed: true
# frozen_string_literal: true

module Api::Internal::Twirp::ActionsResults
  module Core
    module V1
      class CreateArtifact
        attr_reader :req, :env

        def self.call(request, env)
          new(request, env).call
        end

        def initialize(request, env)
          @req = request
          @env = env
        end

        def call
          return Twirp::Error.not_found("check suite does not exist", argument: "check_suite_id") unless check_suite
          return Twirp::Error.not_found("workflow run does not exist for check suite", argument: "check_suite_id") unless check_suite.workflow_run

          expires_at_time = req.expires_at&.to_time
          return Twirp::Error.invalid_argument("must set expires_at", argument: "expires_at") unless expires_at_time
          return Twirp::Error.invalid_argument("must set non-zero expires_at", argument: "expires_at") if expires_at_time.to_i.zero?

          artifact = Artifact.create(
            repository_id: check_suite.repository_id,
            check_suite_id: check_suite.id,
            # https://github.com/github/c2c-actions-checks/issues/500
            workflow_run_id: check_suite.workflow_run.id,
            name: req.name,
            size: req.size,
            source_url: req.source_url,
            expires_at: expires_at_time,
            upload_hash: req.to_h[:hash] || nil, # .hash is an internal method, unfortunate naming
          )

          { artifact_id: artifact.id }
        end

        private

        def check_suite
          @check_suite ||= CheckSuite.find_by(id: req.check_suite_id)
        end
      end
    end
  end
end
