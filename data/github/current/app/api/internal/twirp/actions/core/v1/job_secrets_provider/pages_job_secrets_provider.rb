# typed: true
# frozen_string_literal: true

module Api::Internal::Twirp::Actions
  module Core
    module V1
      module JobSecretsProvider
        class PagesJobSecretsProvider
          CODEPATH_PAGES_JOB_SECRETS_PROVIDER = "pages/job_secrets_provider"

          def initialize(repository, workflow_run, bare_job_name, environment_name, is_hosted_runner, dynamic_workflow)
            @repository = repository
            @workflow_run = workflow_run
            @bare_job_name = bare_job_name
            @environment_name = environment_name
            @is_hosted_runner = is_hosted_runner
            @dynamic_workflow = dynamic_workflow
          end

          def get_secrets
            return {} unless @repository.protected_by_ip_allowlist?

            installation = IntegrationInstallation
              .with_repository(@repository)
              .where(integration_id: GitHub.pages_github_app.id)
              .first

            return {} unless installation

            result = ScopedIntegrationInstallation::Creator
              .perform_with_cache(installation, repositories: [@repository], entry_point: :twirp_api_pages_job_secrets_provider)

            if result.failed?
              Failbot.report(
                ScopedIntegrationInstallation::Result::Error.new(result.error),
                 app: "pages",
              )
              return {}
            end

            _, token = result.installation.generate_token(code_path: CODEPATH_PAGES_JOB_SECRETS_PROVIDER)

            {
              "GITHUB_PAGES_TOKEN": token,
            }
          end
        end
      end
    end
  end
end
