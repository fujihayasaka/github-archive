# typed: true
# frozen_string_literal: true

module Api::Internal::Twirp::Actions
  module Core
    module V1
      # GetIntegrationJobSecrets allows integrations to supply secrets for an Actions workflow job just before the job
      # starts. The integration_name passed to run_dynamic_workflow is used to retrieve secrets from integration-owned
      # code.
      #
      # Integrators:
      # Map your integration name to your secrets provider code in #get_integration_secrets. Your provider should
      # return a hash of secret name (string or symbol) to secret value (string). Secret names should start with the
      # "GITHUB_" prefix to avoid overlap with user-provided secrets.
      class GetIntegrationJobSecrets
        attr_reader :req

        GITHUB_TOKEN_SECRET_NAME = "GITHUB_TOKEN".freeze

        def self.call(request)
          new(request).call
        end

        def initialize(request)
          @req = request
          GitHub.current_span&.set_attribute("gh.integration.name", integration_name) if integration_name.present?
        end

        def call
          return Twirp::Error.invalid_argument("missing integration_name", argument: "integration_name") if integration_name.blank?
          return Twirp::Error.not_found("repository does not exist", argument: "repository_id") unless repository
          return Twirp::Error.not_found("workflow_run does not exist", argument: "workflow_run_id") unless workflow_run

          if repository.feature_enabled?(:actions_log_integration_job_secret_errors)
            begin
              process_secrets
            rescue => e # rubocop:disable Lint/GenericRescue
              GitHub.logger.error("Error getting integration job secrets", {
                :exception => e,
                "code.namespace" => self.class.name,
                "code.function" => "call",
                "gh.catalog_service" => "github/actions",
                "gh.repo.id" => repository.id,
              })

              # Preserve the original exception
              raise e
            end
          else
            process_secrets
          end
        end

        def process_secrets
          # Using failed_precondition (response code 412) instead of a 5xx class error to avoid the client needlessly retrying.
          return Twirp::Error.failed_precondition("Integration #{integration_name} uses unreserved secret names: #{unreserved_secret_names.join(", ")}") if unreserved_secret_names.present?
          return Twirp::Error.failed_precondition("Integration #{integration_name} overrides #{GITHUB_TOKEN_SECRET_NAME}") if secret_names.include?(GITHUB_TOKEN_SECRET_NAME)

          GitHub.dogstats.increment("actions.twirp.get_integration_job_secrets", tags: [
            "integration_name:#{integration_name}",
            "providing_secrets:#{encrypted_secrets.present?}",
          ])

          {
            encrypted_secrets: encrypted_secrets
          }
        end

        # Integrations should use the reserved prefix GITHUB_ to avoid conflicts with user-provided secrets.
        def unreserved_secret_names
          @unreserved_secret_names ||= secret_names.reject do |secret_name|
            secret_name.start_with?(GitHub::KredzClient::Credz::SECRET_KEY_RESERVED_PREFIX)
          end
        end

        def secret_names
          plaintext_secrets.keys
        end

        def encrypted_secrets
          return @encrypted_secrets if defined?(@encrypted_secrets)

          @encrypted_secrets = plaintext_secrets.transform_values do |v|
            # Currently we skip Earthsmoke encryption for enterprise. Earthsmoke was originally its own service, not available in the enterprise environments.
            unencoded_value = if GitHub.enterprise?
              v
            else
              DietEarthsmoke::Key.new(Platform::EncryptionKeys::CUSTOM_TASKS).seal(v, scope: scope)
            end

            Base64.strict_encode64(unencoded_value)
          end
        end

        def plaintext_secrets
          return @plaintext_secrets if defined?(@plaintext_secrets)

          @plaintext_secrets = canonicalize_secrets(get_integration_secrets)
        end

        def get_integration_secrets
          case integration_name
          when Apps::Privileged::Codespaces::PREBUILD_DYNAMIC_WORKFLOW_INTEGRATION_NAME
            JobSecretsProvider::CodespacesJobSecretsProvider
              .new(repository, workflow_run, bare_job_name, environment_name, is_hosted_runner, dynamic_workflow)
              .get_secrets

          # Dependabot's integration slug is used when they queue dynamic workflows via the API
          when GitHub.dependabot_github_app_slug
            JobSecretsProvider::DependabotJobSecretsProvider
              .new(repository, workflow_run, bare_job_name, environment_name, is_hosted_runner, dynamic_workflow)
              .get_secrets

          when "pages" # it's not Apps::Privileged::Pages::INTEGRATION_NAME
            JobSecretsProvider::PagesJobSecretsProvider
              .new(repository, workflow_run, bare_job_name, environment_name, is_hosted_runner, dynamic_workflow)
              .get_secrets

          when "github-code-scanning" # The slug from Apps::Privileged::CodeScanning is github-advanced-security
            JobSecretsProvider::PrivateRegistryJobSecretsProvider
              .new(repository, workflow_run, bare_job_name, environment_name, is_hosted_runner, dynamic_workflow)
              .get_secrets

          when Apps::Privileged::CopilotSWEAgent::SLUG
            # This endpoint is called when sweagentd triggers a Dynamic Workflow execution
            # And the request comes from Actions for Workflow specific secrets - so there is not a user
            return {} unless repository.copilot_swe_agent_enabled?(nil)

            JobSecretsProvider::CopilotSweAgentJobSecretsProvider
              .new(repository, workflow_run, bare_job_name, environment_name, is_hosted_runner, dynamic_workflow)
              .get_secrets

          else
            {}
          end
        end

        def canonicalize_secrets(secrets)
          secrets.transform_keys do |secret_name|
            secret_name.to_s.upcase
          end
        end

        def scope
          repository.id.to_s
        end

        def integration_name
          req.integration_name
        end

        def repository
          return @repository if @repository

          begin
            @repository = Repositories::Public.find_active!(req.repository_id)
          rescue ActiveRecord::RecordNotFound
          end
        end

        def workflow_run
          return @workflow_run if @workflow_run

          @workflow_run = repository.workflow_runs.find_by_id(req.workflow_run_id)
        end

        # The job name used in the workflow, without any matrix strategy suffix
        def bare_job_name
          req.bare_job_name
        end

        # The environment targeted by the job, if any.
        def environment_name
          req.environment_name
        end

        def is_hosted_runner
          req.is_hosted_runner
        end

        def dynamic_workflow
          req.dynamic_workflow
        end
      end
    end
  end
end
