# typed: true
# frozen_string_literal: true

module Api::Internal::Twirp::Actions
  module Core
    module V1
      module JobSecretsProvider
        class CodeScanningJobSecretsProvider

          def initialize(repository, workflow_run, bare_job_name, environment_name, is_hosted_runner, dynamic_workflow)
            @repository = repository
            @workflow_run = workflow_run
            @bare_job_name = bare_job_name
            @environment_name = environment_name
            @is_hosted_runner = is_hosted_runner
            @dynamic_workflow = dynamic_workflow
          end

          EXAMPLE = [{
              "type": "maven_repository",
              "url": "https://maven.pkg.github.com/dsp-testing/*",
              "username": "marcogario",
              "password": "ghp_token"
          }]

          def get_secrets
            {
              "GITHUB_REGISTRIES_PROXY": EXAMPLE.to_json,
            }
          end
        end
      end
    end
  end
end
