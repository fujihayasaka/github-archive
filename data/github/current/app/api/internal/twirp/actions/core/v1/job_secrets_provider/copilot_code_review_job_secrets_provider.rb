# typed: true
# frozen_string_literal: true

module Api::Internal::Twirp::Actions
  module Core
    module V1
      module JobSecretsProvider
        class CopilotCodeReviewJobSecretsProvider
          include GitHub::Memoizer

          CODEPATH_COPILOT_CODE_REVIEW_JOB_SECRETS_PROVIDER = "copilot_code_review/job_secrets_provider"
          COPILOT_DISABLED_IN_MULTI_TENANT_MESSAGE = T.let("not_used_in_multitenant", String)
          ACCESS_ENTRY_POINT = :twirp_api_copilot_code_review_job_secrets_provider
          CAPI_INTEGRATION_ID = "copilot-pr-reviews".freeze

          class CopilotCodeReviewJobSecretsError < StandardError; end
          class GetSecretsError < CopilotCodeReviewJobSecretsError; end
          class NotFoundError < CopilotCodeReviewJobSecretsError; end
          class InvalidArgumentError < CopilotCodeReviewJobSecretsError; end

          def initialize(repository, dynamic_workflow)
            @repository = repository
            @dynamic_workflow = dynamic_workflow
          end

          sig { returns(T::Hash[Symbol, String]) }
          def get_secrets
            app_id = @dynamic_workflow&.inputs&.to_h&.dig("COPILOT_AGENT_APP_ID")
            # If COPILOT_AGENT_APP_ID is not set, we return an empty hash.
            # This allows dynamic workflows that are not related to Copilot Agent to proceed without errors.
            return {} if app_id.blank?
            integration = Integration.find_by(id: app_id)
            raise NotFoundError, "integration not found for COPILOT_AGENT_APP_ID: #{app_id}" if integration.nil?

            raise NotFoundError, "repository is missing" if @repository.nil?

            user_id = @dynamic_workflow.inputs["COPILOT_AGENT_ACTOR_ID"]
            raise NotFoundError, "COPILOT_AGENT_ACTOR_ID is missing from inputs" if user_id.nil?
            user = User.find_by(id: user_id)
            raise NotFoundError, "user does not exist" if user.nil?

            # In Proxima (multi-tenant) the agent downloads binaries from CCR directly and
            # does not need an artifact-repo token, so leave it as an empty string.
            artifact_repo_token = ""
            if !GitHub.multi_tenant_enterprise?
              artifact_repo, additional_artifact_repositories = get_repositories(
                artifact_repository_nwo: @dynamic_workflow.inputs["COPILOT_AGENT_ARTIFACT_REPO"],
                additional_artifact_repositories_and_versions_string: @dynamic_workflow.inputs["ADDITIONAL_ARTIFACT_REPOSITORIES_AND_VERSIONS"] || "",
              )
              artifact_repo_token = mint_repo_scoped_installation_token(integration:, artifact_repo:, additional_artifact_repositories:)
            end

            user_token = mint_token_for_capi(integration:, user:)

            secrets = {
              "GITHUB_COPILOT_API_TOKEN": user_token,
              "GITHUB_COPILOT_INTEGRATION_ID": CAPI_INTEGRATION_ID,
              "GITHUB_AGENT_ARTIFACT_REPO_TOKEN": artifact_repo_token,
            }

            secrets
          end

          # Mint the CAPI token for this review. Defaults to a user-to-server (`ghu_`) token
          # for backward compatibility; when the org has direct-org-billing on and the
          # cutover feature flag is enabled, mints a server-to-server (`ghs_`) installation
          # token instead so CAPI bills the org directly (mirrors the CCA pattern). The
          # predicate also returns false when the user holds their own Copilot seat, so
          # seat-holders in DOB orgs continue to be billed to their seat.
          sig { params(integration: Integration, user: User).returns(String) }
          def mint_token_for_capi(integration:, user:)
            access = ::PullRequests::Copilot::CodeReviewAccess.new(actor: user, current_repository: @repository)
            if access.should_mint_org_token?
              mint_repo_scoped_installation_api_token(integration:)
            else
              mint_repo_scoped_user_token(integration:, user:)
            end
          end

          # Mint an org-scoped installation token (`ghs_`) for the CCR integration against
          # the repository's owner, scoped to the repository. Used on the org-billed path so
          # CAPI sees a TypeOrg actor.
          sig { params(integration: Integration).returns(String) }
          def mint_repo_scoped_installation_api_token(integration:)
            repo = T.must(@repository)
            repo_owner = repo.owner
            raise NotFoundError, "repo_owner is missing" if repo_owner.nil?

            result = ActiveRecord::Base.connected_to(role: :writing) do
              SiteScopedIntegrationInstallation::Creator.perform(
                integration,
                repo_owner,
                repositories: [repo],
                permissions: {
                  "metadata" => :read,
                  "contents" => :read,
                  "pull_requests" => :read,
                  "actions" => :write,
                  "issues" => :read,
                  "copilot_requests" => :write,
                },
                entry_point: ACCESS_ENTRY_POINT,
              )
            end

            if result.failed?
              raise GetSecretsError, "Failed to create scoped installation: #{result.error.presence || 'unknown error'}"
            end

            response = result.installation.generate_token(
              code_path: CODEPATH_COPILOT_CODE_REVIEW_JOB_SECRETS_PROVIDER,
              redis_with_mysql_fallback: ServerToServerTokens.domain.redis_with_mysql_fallback?([
                integration, repo_owner
              ])
            )

            case response
            when GH::Result::Ok
              response.value.token_value
            else
              Failbot.report(
                ScopedIntegrationInstallation::Result::Error.new(response.message),
              )
              raise GetSecretsError, "Failed to generate token for scoped installation: #{response.message}"
            end
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

              scoped_access, error = integration.convert_to_scoped_access(
                new_access,
                repo_owner,
                permissions: {
                  "metadata" => :read,
                  "contents" => :read,
                  "pull_requests" => :read,
                  "actions" => :write,
                  "issues" => :read,
                },
                resources: {
                  repository_ids: [T.must(@repository).id],
                },
                entry_point: ACCESS_ENTRY_POINT,
              )
              if error
                raise GetSecretsError, error
              end

              token, _ = T.must(scoped_access).redeem(extended_expiry: true)
              token
            end
          end

          sig { params(artifact_repository_nwo: String, additional_artifact_repositories_and_versions_string: String).returns([Repository, T::Array[Repository]]) }
          def get_repositories(artifact_repository_nwo:, additional_artifact_repositories_and_versions_string:)
            artifact_repository = Repository.nwo(artifact_repository_nwo)
            raise NotFoundError, "artifact_repo not found for COPILOT_AGENT_ARTIFACT_REPO: #{artifact_repository_nwo}" if artifact_repository.nil?

            additional_artifact_repositories_and_versions = {}
            unless additional_artifact_repositories_and_versions_string.empty?
              begin
                additional_artifact_repositories_and_versions = JSON.parse(additional_artifact_repositories_and_versions_string)
              rescue JSON::ParserError
                raise InvalidArgumentError, "ADDITIONAL_ARTIFACT_REPOSITORIES_AND_VERSIONS is not valid JSON"
              end
              raise InvalidArgumentError, "ADDITIONAL_ARTIFACT_REPOSITORIES_AND_VERSIONS must be JSON object" unless additional_artifact_repositories_and_versions.is_a? Hash
            end

            additional_artifact_repositories = []
            additional_artifact_repositories_and_versions.keys.each do |nwo|
              repo = Repository.nwo(nwo.strip)
              raise NotFoundError, "additional artifact_repo not found for ADDITIONAL_ARTIFACT_REPOSITORIES_AND_VERSIONS: #{nwo.strip}" if repo.nil?
              additional_artifact_repositories.push(repo)
            end

            [artifact_repository, additional_artifact_repositories]
          end

          sig { params(integration: Integration, artifact_repo: Repository, additional_artifact_repositories: T::Array[Repository]).returns(String) }
          def mint_repo_scoped_installation_token(integration:, artifact_repo:, additional_artifact_repositories:)
            result = SiteScopedIntegrationInstallation::Creator.perform(
              integration,
              artifact_repo.owner,
              repositories: [artifact_repo, *additional_artifact_repositories],
              permissions: {
                "metadata" => :read,
                "contents" => :read,
                # "packages" => :read, TODO: add packages only in the near future
              },
              entry_point: ACCESS_ENTRY_POINT
            )
            if result.failed?
              raise GetSecretsError, "Failed to create scoped installation: #{result.error}" if result.error.present?
            end

            response = result.installation.generate_token(
              code_path: CODEPATH_COPILOT_CODE_REVIEW_JOB_SECRETS_PROVIDER,
              redis_with_mysql_fallback: ServerToServerTokens.domain.redis_with_mysql_fallback?([
                integration, artifact_repo.owner
              ])
            )

            case response
            when GH::Result::Ok
              response.value.token_value
            when GH::Result::Error
              Failbot.report(
                ScopedIntegrationInstallation::Result::Error.new(response.message),
              )
              raise GetSecretsError, "Failed to generate token for scoped installation: #{response.message}"
            end
          end
        end
      end
    end
  end
end
