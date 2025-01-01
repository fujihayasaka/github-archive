# typed: strict
# frozen_string_literal: true

module Api::Internal::Twirp::Actions
  module Core
    module V1
      module JobSecretsProvider
        class PrivateRegistryJobSecretsProvider

          sig do
            params(
              repository: T.nilable(Repository),
              workflow_run: T.nilable(Actions::WorkflowRun),
              bare_job_name: T.nilable(String),
              environment_name: T.nilable(String),
              is_hosted_runner: T.nilable(T::Boolean),
              dynamic_workflow: T.nilable(MonolithTwirp::Actions::Core::V1::DynamicWorkflow),
            ).void
          end
          def initialize(repository, workflow_run, bare_job_name, environment_name, is_hosted_runner, dynamic_workflow)
            @repository = repository
            @workflow_run = workflow_run
            @bare_job_name = bare_job_name
            @environment_name = environment_name
            @is_hosted_runner = is_hosted_runner
            @dynamic_workflow = dynamic_workflow
          end

          sig { returns(T::Hash[Symbol, String]) }
          def get_secrets
            return {} if repository.nil? || organization.nil?

            {
              "GITHUB_REGISTRIES_PROXY": encoded_credentials,
            }
          end

          private

          sig { returns(T.nilable(Repository)) }
          attr_reader :repository

          sig { returns(T.nilable(User)) }
          def organization
            repo = repository

            return nil if repo.nil?
            return nil unless repo.owner&.organization? || repo.organization_id == repo.owner_id

            repo.owner
          end

          sig { returns(String) }
          def encoded_credentials
            Base64.strict_encode64(GitHub::JSON.encode(credentials))
          end

          sig { returns(T::Array[T::Hash[Symbol, String]]) }
          def credentials
            ActiveRecord::Base.connected_to(role: :reading) do
              PrivateRegistry.credentials_for_repository(T.must(repository), actor: T.must(organization), include_value: true)
            end
          end
        end
      end
    end
  end
end
