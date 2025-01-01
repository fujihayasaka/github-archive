# typed: true
# frozen_string_literal: true

module Api::Internal::Twirp::Actions
  module Core
    module V1
      module JobSecretsProvider
        class CopilotSweAgentJobSecretsProvider
          include GitHub::Memoizer

          COPILOT_SWE_AGENT_JOB_SECRETS_PROVIDER = "copilot_swe_agent/job_secrets_provider"

          class CopilotSweAgentJobSecretsError < StandardError; end
          class GetSecretsError < CopilotSweAgentJobSecretsError; end
          class NotFoundError < CopilotSweAgentJobSecretsError; end

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
            raise NotFoundError, "repository is missing" if @repository.nil?
            raise NotFoundError, "workflow_run is missing" if @workflow_run.nil?
            raise NotFoundError, "dynamic_workflow is missing" if @dynamic_workflow.nil?

            raise NotFoundError, "dynamic_workflow.inputs is missing" if @dynamic_workflow.inputs.nil?

            user_id = @dynamic_workflow.inputs["COPILOT_AGENT_ACTOR_ID"]
            raise NotFoundError, "COPILOT_AGENT_ACTOR_ID is missing from inputs" if user_id.nil?

            user = User.find_by(id: user_id)
            raise NotFoundError, "user does not exist" if user.nil?

            # Copilot SWE Agent does not support re-running the job via Actions CI. So return empty job/cred token to the
            # the Copilot SWE Agent job if the this is a re-run job via Actions CI.
            # This will fail the re-run Copilot SWE Agent job which is expected behavior.
            if @workflow_run.has_multiple_attempts && !user.feature_enabled?(:copilot_swe_agent_job_secrets_provider_re_run)
              GitHub.logger.info(
                "Re-running Copilot SWE Agent jobs via Actions CI is not supported.",
                "code.namespace" => self.class.name,
                "code.function" => __method__,
                "gh.repository.id" => @repository.id,
                "gh.workflow_run.id" => @workflow_run.id,
              )
              return {}
            end

            integration = ::Apps::Privileged.integration(:copilot_swe_agent)
            raise NotFoundError, "integration does not exist" if integration.nil?

            action_codeload_url = get_action_codeload_url(integration)

            user_token = mint_repo_scoped_user_token(integration: integration, user: user)
            server_token = mint_repo_scoped_installation_token(integration: integration)

            {
              "GITHUB_COPILOT_GIT_TOKEN": server_token,
              "GITHUB_COPILOT_API_TOKEN": user_token,
              "GITHUB_COPILOT_INTEGRATION_ID": "copilot-developer",
              "GITHUB_COPILOT_ACTION_DOWNLOAD_URL": action_codeload_url,
            }
          rescue StandardError => e # rubocop:todo Lint/GenericRescue
            raise GetSecretsError, "Error in get_secrets: #{e.message}"
          end

          private

          sig { returns(Repository) }
          memoize def action_repo
            Repository.nwo("github/copilot-developer-action")
          end

          sig { params(integration: Integration).returns(String) }
          def get_action_codeload_url(integration)
            result = ActiveRecord::Base.connected_to(role: :writing) do
              SiteScopedIntegrationInstallation::Creator.perform(
                integration,
                action_repo.owner,
                repositories: [action_repo],
                permissions: {
                  "metadata" => :read,
                  "contents" => :read,
                },
                entry_point: :twirp_api_copilot_swe_agent_job_secrets_provider
              )
            end

            ac = action_repo.archive_command(action_repo.default_branch, "tar.gz")
            ac.codeload_url(result.installation.bot)
          end

          # Create a new scoped access for the user to the repository. This uses global installations to
          # ensure we're not creating a new installation.
          sig { params(integration: Integration, user: User).returns(String) }
          def mint_repo_scoped_user_token(integration:, user:)
            repo_owner = T.must(@repository).owner
            raise NotFoundError, "repo_owner is missing" if repo_owner.nil?

            # Need to be in a writing role to update records with the scoped installation
            ActiveRecord::Base.connected_to(role: :writing) do
              # Create a fresh access grant for the integration/user
              new_access = integration.grant(user)

              # Check if SAML would be enforced for this repository and if so create a credential authorization grant for them.
              # This should be safe to do because all mechanisms to trigger this secret provider already go through appropriate SAML CAP filtering
              # either in the API or in the Rails controllers (ex: assigning an issue to Copilot).
              if repo_owner.organization? && Organization::SamlEnforcementPolicy.new(organization: repo_owner, user:).enforced?
                if !Organization::CredentialAuthorization.by_organization_credential(organization: repo_owner, credential: new_access).active.exists?
                  authorization = Organization::CredentialAuthorization.grant(organization: repo_owner, credential: new_access, actor: user)
                  raise GetSecretsError, "Could not create credential authorization grant. Org: #{repo_owner.id}, user: #{user.id}" if authorization.nil?
                end
              end

              scoped_access, error = integration.grant_scoped_access_from(
                new_access,
                repo_owner,
                permissions: {
                  "metadata" => :read,
                  "contents" => :read,
                  "issues" => :read,
                  "pull_requests" => :read,
                  "actions" => :read,
                },
                resources: {
                  repository_ids: [T.must(@repository).id],
                },
                entry_point: :twirp_api_copilot_swe_agent_job_secrets_provider,
              )
              if error
                raise GetSecretsError, error
              end

              token, _ = scoped_access.redeem(extended_expiry: true)
              token
            end
          end

          # Mint a repo-scoped token for the installation on the repository.
          # This token will be used to `git push` as Copilot, not as Actions.
          # So, it only needs some limited permissions.
          def mint_repo_scoped_installation_token(integration:)
            result = ActiveRecord::Base.connected_to(role: :writing) do
              SiteScopedIntegrationInstallation::Creator.perform(
                integration,
                T.must(@repository).owner,
                repositories: [@repository],
                permissions: {
                  "contents" => :write,
                  "metadata" => :read,
                  "workflows" => :write,
                },
                entry_point: :twirp_api_copilot_swe_agent_job_secrets_provider
              )
            end

            case response = result.installation.generate_token(code_path: COPILOT_SWE_AGENT_JOB_SECRETS_PROVIDER)
            when GH::Result::Ok
              response.value.token_value
            when GH::Result::Error
              Failbot.report(
                ScopedIntegrationInstallation::Result::Error.new(response.message),
                app: "sweagentd",
              )
              raise GetSecretsError, "Failed to generate token for scoped installation: #{response.message}"
            end
          end
        end
      end
    end
  end
end
