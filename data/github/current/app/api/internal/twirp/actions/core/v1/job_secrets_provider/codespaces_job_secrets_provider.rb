# typed: true
# frozen_string_literal: true

module Api::Internal::Twirp::Actions
  module Core
    module V1
      module JobSecretsProvider
        class CodespacesJobSecretsProvider
          attr_reader :repository

          class Error < Codespaces::Error; end

          class CodespacesJobSecretsError < Error
            def initialize(message, backtrace)
              super(message)
              set_backtrace backtrace
            end
          end

          class GetSecretsError < CodespacesJobSecretsError; end
          class PrebuildSecretsError < CodespacesJobSecretsError; end
          class AssembledSecretsError < CodespacesJobSecretsError; end

          def initialize(repository, workflow_run, bare_job_name, environment_name, is_hosted_runner, dynamic_workflow)
            @repository = repository
            @workflow_run = workflow_run
            @bare_job_name = bare_job_name
            @environment_name = environment_name
            @is_hosted_runner = is_hosted_runner
            @dynamic_workflow = dynamic_workflow
          end

          def get_secrets
            begin
              {
                  "GITHUB_INTEGRATION_NAME": ::Apps::Privileged::Codespaces::PREBUILD_DYNAMIC_WORKFLOW_INTEGRATION_NAME,
                  "GITHUB_CODESPACE_AGENT_SECRETS": serialized_secrets,
                  "GITHUB_CODESPACES_INTERNAL_URL": "codespaces_internal/prebuilds/repository",
                  "GITHUB_CODESPACES_LOG_PATH": "/tmp/VSFeedbackVSRTCLogs",
                  "GITHUB_CODESPACES_LOCATION_KEY": "vscs_location",
                  "GITHUB_CODESPACES_TARGET_KEY": "vscs_target",
                  "GITHUB_CODESPACES_TARGET_URL_KEY": "vscs_target_url"
              }
          rescue AssembledSecretsError, PrebuildSecretsError => e
            raise e
          rescue => e # rubocop:todo Lint/GenericRescue
            raise GetSecretsError.new(e.message, e.backtrace)
            end
          end


          private

          def serialized_secrets
            @serialized_secrets ||= GitHub::JSON.encode(assembled_secrets)
          end

          def assembled_secrets
            return @assembled_secrets if defined?(@assembled_secrets)

            begin
              @assembled_secrets = ::Codespaces::AssembleSecrets.call(
                user: nil,
                github_token: prebuild_secrets[:github_token] || "",
                codespace_token: nil,
                repository: repository,
                user_secrets: prebuild_secrets[:secrets],
              )
            rescue PrebuildSecretsError => e
              raise e
            rescue => e # rubocop:todo Lint/GenericRescue
              raise AssembledSecretsError.new(e.message, e.backtrace)
            end
          end

          def prebuild_secrets
            return @prebuild_secrets if defined?(@prebuild_secrets)

            begin
              @prebuild_secrets = ::Codespaces::GetPrebuildSecrets.call(
                repository: repository,
                pat_secret_required: true,
                branch: branch,
                entry_point: :twirp_api_internal_twirp_actions_core_v1_job_secrets_provider_codespaces_job_secrets_provider,
              )
            rescue => e # rubocop:todo Lint/GenericRescue
              raise PrebuildSecretsError.new(e.message, e.backtrace)
            end
          end

          def branch
            ref = repository.refs.find(@dynamic_workflow&.ref)
            ref&.name
          end
        end
      end
    end
  end
end
