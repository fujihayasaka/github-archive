# typed: strict
# frozen_string_literal: true

require "monolith-twirp-sweagentd-sweagentd"

module Api::Internal::Twirp::Sweagentd
  module Sweagentd
    module V1
      # Handler for the MonolithTwirp::Sweagentd::Sweagentd::V1::SweagentdAPIService
      class SweagentdApiHandler < Api::Internal::Twirp::Handler
        include GitHub::Memoizer

        sig do
          params(
            rack_env: T::Hash[T.untyped, T.untyped], # rubocop:disable Sorbet/ForbidTUntyped
            env: T::Hash[T.untyped, T.untyped], # rubocop:disable Sorbet/ForbidTUntyped
          ).void
        end
        def before_rpc(rack_env, env)
          if (client_key = rack_env[:request_hmac_key])
            env[:client_name] = GitHub.api_internal_twirp_hmac_settings[client_key]
          end
          env[:internal_client_id] = rack_env[:internal_client_id]
          env[:real_ip]            = rack_env["HTTP_X_CLIENT_IP"]
          env[:request_id]         = rack_env["HTTP_X_GITHUB_REQUEST_ID"]
        end

        allow_access_for :client, allowed_clients: %w[
          sweagentd
        ]
        handles_service MonolithTwirp::Sweagentd::SweagentdAPI::V1::SweagentdAPIService
        connected_to_writing_for :create_pull_request

        # Public: Implementation of the m_c_p_configuration_for_repository Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Sweagentd::SweagentdAPI::V1::MCPConfigurationForRepositoryRequest.
        # env - The Twirp environment as a Hash.
        # Returns the Twirp response as a Hash indicating whether the repository has MCP enabled and what the configuration is.
        sig do
          params(
            req: MonolithTwirp::Sweagentd::SweagentdAPI::V1::MCPConfigurationForRepositoryRequest,
            env: T::Hash[T.untyped, T.untyped], # rubocop:disable Sorbet/ForbidTUntyped
          ).returns(
            T.any(
              MonolithTwirp::Sweagentd::SweagentdAPI::V1::MCPConfigurationForRepositoryResponse,
              Twirp::Error,
            )
          )
        end
        def m_c_p_configuration_for_repository(req, env)
          GitHub.tracer.in_span("sweagentd.twirp.mcp_configuration_for_repository", kind: :internal) do
            GitHub.dogstats.distribution_time("sweagentd.twirp.mcp_configuration_for_repository") do
              return Twirp::Error.invalid_argument("Repository ID is required.", argument: "repository_id") if req.repository_id.blank?
              return Twirp::Error.invalid_argument("User ID is required.", argument: "user_id") if req.user_id.blank?

              repository = Repository.find_by(id: req.repository_id)
              return Twirp::Error.not_found("Repository ID '#{req.repository_id}' not found.") if !repository

              # TODO: Provide policy lookup by user for MCP enablement here

              matching_swe_configuration = Copilot::SweAgentConfiguration.find_by(resource: repository, resource_type: "Repository")
              user = User.find_by(id: req["user_id"])
              return Twirp::Error.not_found("User ID '#{req["user_id"]}' not found.") if !user

              return MonolithTwirp::Sweagentd::SweagentdAPI::V1::MCPConfigurationForRepositoryResponse.new(
                is_mcp_enabled: Copilot::Public::User.new(user).mcp_enabled?,
                mcp_configuration_json: matching_swe_configuration&.mcp_configuration,
              )
            end
          end
        end

        # Public: Implementation of the configuration_for_repository Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Sweagentd::SweagentdAPI::V1::ConfigurationForRepositoryRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash indicating whether the repository
        # has the copilot_swe_agent_enabled feature, or a Twirp::Error if the
        # repository is not found.
        sig do
          params(
            req: MonolithTwirp::Sweagentd::SweagentdAPI::V1::ConfigurationForRepositoryRequest,
            env: T::Hash[T.untyped, T.untyped], # rubocop:disable Sorbet/ForbidTUntyped
          ).returns(
            T.any(
              MonolithTwirp::Sweagentd::SweagentdAPI::V1::ConfigurationForRepositoryResponse,
              Twirp::Error,
            )
          )
        end
        def configuration_for_repository(req, env)
          GitHub.tracer.in_span("sweagentd.twirp.configuration_for_repository", kind: :internal) do
            GitHub.dogstats.distribution_time("sweagentd.twirp.configuration_for_repository") do
              return Twirp::Error.invalid_argument("Repository ID is required.", argument: "repository_id") if req.repository_id.blank?
              repository = Repository.find_by(id: req["repository_id"])
              return Twirp::Error.not_found("Repository ID '#{req["repository_id"]}' not found.") if !repository

              return Twirp::Error.invalid_argument("User ID is required.", argument: "user_id") if req.user_id.blank?
              user = User.find_by(id: req["user_id"])
              return Twirp::Error.not_found("User ID '#{req["user_id"]}' not found.") if !user

              return MonolithTwirp::Sweagentd::SweagentdAPI::V1::ConfigurationForRepositoryResponse.new(
                is_sweagentd_enabled: repository.copilot_swe_agent_enabled?(user)
              )
            end
          end
        end

        # Public: Implementation of the create_pull_request Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Sweagentd::SweagentdAPI::V1::CreatePullRequestRequest.
        # env - The Twirp environment as a Hash.
        #
        # Creates a PullRequest according to the passed request.
        sig do
          params(
            req: MonolithTwirp::Sweagentd::SweagentdAPI::V1::CreatePullRequestRequest,
            env: T::Hash[T.untyped, T.untyped], # rubocop:disable Sorbet/ForbidTUntyped
          ).returns(
            T.any(
              T::Hash[T.untyped, T.untyped], # rubocop:disable Sorbet/ForbidTUntyped
              Twirp::Error,
            )
          )
        end
        def create_pull_request(req, env)
          GitHub.tracer.in_span("sweagentd.twirp.create_pull_request", kind: :internal) do
            GitHub.dogstats.distribution_time("sweagentd.twirp.create_pull_request") do
              return Twirp::Error.invalid_argument("must be provided", argument: "repository_id") unless req.repository_id.present? && req.repository_id.nonzero?
              return Twirp::Error.invalid_argument("must be provided", argument: "head_branch_name") unless req.head_branch_name.present?
              return Twirp::Error.invalid_argument("must be provided", argument: "pr_name") unless req.pr_name.present?
              return Twirp::Error.invalid_argument("must be provided", argument: "pr_description") unless req.pr_description.present?
              return Twirp::Error.invalid_argument("must be provided", argument: "attribution_user_id") unless req.attribution_user_id.present?
              return Twirp::Error.invalid_argument("must be provided", argument: "draft") if req.draft.nil?

              repository = ::Repositories::Public.find_active(req.repository_id)
              return Twirp::Error.not_found("repository not found") if repository.nil?

              # Need to create a site-scoped installation for the bot to have access
              # to create the pull request.
              result = ActiveRecord::Base.connected_to(role: :writing) do
                SiteScopedIntegrationInstallation::Creator.perform(
                  integration,
                  repository.owner,
                  repositories: [repository],
                )
              end
              copilot_bot = result.installation.bot

              attribution_user = User.find_by(id: req.attribution_user_id)
              return Twirp::Error.not_found("user does not exist", argument: "attribution_user_id") if attribution_user.nil?

              base_branch = req.base_branch_name.present? ? req.base_branch_name : repository.default_branch

              GitHub.logger.info(
                "Creating padawan pull request",
                "code.namespace": self.class.name,
                "code.function": env[:rpc_method],
                "gh.repo.id": repository.id,
                "gh.pull_request.head_sha": repository.heads.find(req.head_branch_name)&.sha || "not found",
                "gh.pull_request.base_sha": repository.heads.find(base_branch)&.sha || "not found",
                "gh.sweagentd.attributed_user_id": attribution_user.id,
              )
              pull_request = PullRequest.create_for!(repository, {
                title: req.pr_name,
                head: req.head_branch_name,
                base: base_branch,
                body: req.pr_description,
                draft: req.draft,
                user: copilot_bot,
                copilot_attributions: [attribution_user]
              })

              pull_request.issue.add_assignees([copilot_bot, attribution_user]) # domain-isolation-query-violation:ignore:packages/issues (SELECT)

              {
                pull_request: {
                  id: pull_request.id,
                  github_number: pull_request.number,
                  repository_id: pull_request.repository_id,
                }
              }
            end
          end
        end

        # Public: Implementation of the mint_user_to_server_token_for_repo Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Sweagentd::SweagentdAPI::V1::MintUserToServerTokenForRepoRequest.
        # env - The Twirp environment as a Hash.
        #
        # Mints a user to server token for the specified repository.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Sweagentd::SweagentdAPI::V1::MintUserToServerTokenForRepoResponse, or a Twirp::Error.
        sig do
          params(
            req: MonolithTwirp::Sweagentd::SweagentdAPI::V1::MintUserToServerTokenForRepoRequest,
            env: T::Hash[T.untyped, T.untyped], # rubocop:disable Sorbet/ForbidTUntyped
          ).returns(
            T.any(
              MonolithTwirp::Sweagentd::SweagentdAPI::V1::MintUserToServerTokenForRepoResponse,
              Twirp::Error,
            )
          )
        end
        def mint_user_to_server_token_for_repo(req, env)
          GitHub.tracer.in_span("sweagentd.twirp.mint_user_to_server_token_for_repo", kind: :internal) do
            GitHub.dogstats.distribution_time("sweagentd.twirp.mint_user_to_server_token_for_repo") do
              return Twirp::Error.invalid_argument("missing user_id", argument: "user_id") if req.user_id.blank?
              return Twirp::Error.invalid_argument("missing repository_id", argument: "repository_id") if req.repository_id.blank?

              user = User.find_by(id: req.user_id)
              return Twirp::Error.not_found("user does not exist", argument: "user_id") if user.nil?

              repository = Repository.find_by(id: req.repository_id)
              return Twirp::Error.not_found("repository does not exist", argument: "repository_id") if repository.nil?

              repo_owner = repository.owner
              return Twirp::Error.not_found("repository owner does not exist") if repo_owner.nil?

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
                    return Twirp::Error.permission_denied("Could not create credential authorization grant. Org: #{repo_owner.id}, user: #{user.id}") if authorization.nil?
                  end
                end

                scoped_access, error = integration.grant_scoped_access_from(
                  new_access,
                  repo_owner,
                  permissions: {
                    "metadata" => :read,
                    "contents" => :write,
                    "pull_requests" => :read,
                  },
                  resources: {
                    repository_ids: [repository.id],
                  },
                  entry_point: :twirp_api_copilot_swe_agent_api_handler,
                )
                if error
                  return Twirp::Error.permission_denied(error)
                end

                # Sets the expiration for the access and the installation without
                # needing to update all of the `permissions` rows.
                token, _ = scoped_access.redeem(extended_expiry: true)

                MonolithTwirp::Sweagentd::SweagentdAPI::V1::MintUserToServerTokenForRepoResponse.new({
                  token: token
                })
              end
            end
          end
        end

        private

        sig { returns(Integration) }
        memoize def integration
          ::Apps::Privileged.integration(:copilot_swe_agent)
        end
      end
    end
  end
end
