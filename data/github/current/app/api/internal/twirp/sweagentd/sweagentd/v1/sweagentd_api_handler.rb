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

              repository = if FeatureFlag.vexi.enabled?(:repos_by_id_api_twirp, default: false)
                ::Repositories.domain.by_id(req.repository_id)
              else
                Repository.find_by(id: req.repository_id)
              end
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
              repository = if FeatureFlag.vexi.enabled?(:repos_by_id_api_twirp, default: false)
                T.cast(::Repositories.domain.by_id(req["repository_id"]), T.nilable(Repository)) # rubocop:todo GitHub/AvoidCast
              else
                Repository.find_by(id: req["repository_id"])
              end
              return Twirp::Error.not_found("Repository ID '#{req["repository_id"]}' not found.") if !repository

              return Twirp::Error.invalid_argument("User ID is required.", argument: "user_id") if req.user_id.blank?
              user = User.find_by(id: req["user_id"])
              return Twirp::Error.not_found("User ID '#{req["user_id"]}' not found.") if !user

              response_params = {
                is_sweagentd_enabled: repository.copilot_swe_agent_enabled?(user)
              }

              if FeatureFlag.vexi.enabled?(:sweagent_send_enabled, default: false)
                agent = agent_for_bot_id_or_default(req.agent_id)
                return Twirp::Error.not_found("Agent ID '#{req["agent_id"]}' not found.") if !agent

                is_enabled = agent.enabled_for_repository?(repository, user)
                response_params[:is_agent_enabled] = is_enabled
                response_params[:is_sweagentd_enabled] = is_enabled
              end

              # If we're on proxima, resolve a tenant
              if GitHub::Config::Proxima.current_stamp.present?
                tenant = repository.resolve_tenant
                if tenant.present?
                  response_params[:tenant_slug] = tenant.slug
                  response_params[:tenant_id] = tenant.id.to_s
                end
              end

              return MonolithTwirp::Sweagentd::SweagentdAPI::V1::ConfigurationForRepositoryResponse.new(response_params)
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

              attribution_user = User.find_by(id: req.attribution_user_id)
              return Twirp::Error.not_found("user does not exist", argument: "attribution_user_id") if attribution_user.nil?

              base_branch_name = req.base_branch_name.present? ? req.base_branch_name : repository.default_branch
              base_branch = repository.heads.find(base_branch_name)
              return Twirp::Error.not_found("base branch `#{base_branch_name}` not found", argument: "base_branch") if base_branch.nil?

              agent = AgenticApp::CopilotAgent.instance
              if FeatureFlag.vexi.enabled?(:agenthq_mint_token, repository, default: false)
                return Twirp::Error.invalid_argument("unknown agent id", argument: "agent_id") if req.agent_id.blank?
                agent = agent_for_bot_id_or_default(req.agent_id)
                return Twirp::Error.invalid_argument("agent not found", argument: "agent_id") if agent.nil?

                unless agent.global?
                  unless agent.enabled_for_repository?(repository, attribution_user)
                    return Twirp::Error.permission_denied("agent not enabled for repository")
                  end
                end
              end

              integration = agent.integration
              return Twirp::Error.failed_precondition("agent integration is not configured") if integration.nil?

              agent_bot = agent_bot_for_repository(agent, integration, repository)
              return Twirp::Error.permission_denied("agent installation not found for repository") if agent_bot.nil?

              head_branch = repository.heads.find(req.head_branch_name)
              return Twirp::Error.not_found("head branch `#{req.head_branch_name}` not found", argument: "head_branch") if head_branch.nil?

              GitHub.logger.info(
                "Creating padawan pull request",
                "code.namespace": self.class.name,
                "code.function": env[:rpc_method],
                "gh.repo.id": repository.id,
                "gh.pull_request.head_sha": head_branch.sha,
                "gh.pull_request.base_sha": base_branch.sha,
                "gh.sweagentd.attributed_user_id": attribution_user.id,
                "gh.sweagentd.session_id": req.session_id,
              )

              begin
                pull_request = PullRequest.create_for!(repository, {
                  title: req.pr_name,
                  head: head_branch.name,
                  base: base_branch.name,
                  body: req.pr_description,
                  draft: req.draft,
                  user: agent_bot,
                  copilot_attributions: [attribution_user],
                  agent_session_id: req.session_id,
                })
              rescue ActiveRecord::RecordInvalid => e
                # Check if the error is due to a uniqueness violation
                if e.record.errors.details.any? { |_, details| details.any? { |d| d[:error] == :duplicate } }
                  return Twirp::Error.already_exists("failed to create pull request: pull request already exists")
                end

                return Twirp::Error.invalid_argument("failed to create pull request: #{e.record.errors.full_messages.join(', ')}")
              end

              pull_request.issue.add_assignees([agent_bot, attribution_user]) # domain-isolation-query-violation:ignore:packages/issues (SELECT)

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

              repository = ::Repositories::Public.find_active(req.repository_id)
              return Twirp::Error.not_found("repository does not exist", argument: "repository_id") if repository.nil?

              repo_owner = repository.owner
              return Twirp::Error.not_found("repository owner does not exist") if repo_owner.nil?

              agent = AgenticApp::CopilotAgent.instance
              if FeatureFlag.vexi.enabled?(:agenthq_mint_token, repository, default: false)
                return Twirp::Error.invalid_argument("unknown agent id", argument: "agent_id") if req.agent_id.blank?
                agent = agent_for_bot_id_or_default(req.agent_id)
                return Twirp::Error.invalid_argument("agent not found", argument: "agent_id") if agent.nil?

                unless agent.global?
                  unless agent.enabled_for_repository?(repository, user)
                    return Twirp::Error.permission_denied("agent not enabled for repository")
                  end
                end
              end

              integration = agent.integration
              return Twirp::Error.failed_precondition("agent integration is not configured") if integration.nil?

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

        # Public: Implementation of the get_organization_custom_instructions Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Sweagentd::SweagentdAPI::V1::GetOrganizationCustomInstructionsRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the organization's custom instructions for the SWE Agent.
        #
        # Returns the Twirp response as a MonolithTwirp::Sweagentd::SweagentdAPI::V1::GetOrganizationCustomInstructionsResponse, or a Twirp::Error.
        sig do
          params(
            req: MonolithTwirp::Sweagentd::SweagentdAPI::V1::GetOrganizationCustomInstructionsRequest,
            env: T::Hash[T.untyped, T.untyped], # rubocop:disable Sorbet/ForbidTUntyped
          ).returns(
            T.any(
              MonolithTwirp::Sweagentd::SweagentdAPI::V1::GetOrganizationCustomInstructionsResponse,
              Twirp::Error,
            )
          )
        end
        def get_organization_custom_instructions(req, env)
          GitHub.tracer.in_span("sweagentd.twirp.get_organization_custom_instructions", kind: :internal) do
            GitHub.dogstats.distribution_time("sweagentd.twirp.get_organization_custom_instructions") do
              return Twirp::Error.invalid_argument("Organization ID is required.", argument: "organization_id") if req["organization_id"].blank? || req["organization_id"].zero?

              organization = Organization.find_by(id: req["organization_id"])
              return Twirp::Error.not_found("Organization ID '#{req["organization_id"]}' not found.") if !organization

              # Check if organization has Copilot custom instructions feature
              copilot_org = Copilot::Organization.new(organization)
              return Twirp::Error.permission_denied("Organization does not have access to custom instructions.") unless copilot_org.can_use_org_copilot_custom_instructions?

              # Fetch organization's custom instructions with feature flag protection
              instructions_text = Copilot::CustomInstructions.for_sweagentd_organization(organization) || ""

              response = MonolithTwirp::Sweagentd::SweagentdAPI::V1::GetOrganizationCustomInstructionsResponse.new
              response["organization_custom_instructions"] = instructions_text
              return response
            end
          end
        end

        # Public: Implementation of the resolve_user_i_d_to_display_login Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Sweagentd::SweagentdAPI::V1::ResolveUserIDToDisplayLoginRequest.
        # env - The Twirp environment as a Hash.
        #
        # Mints a user to server token for the specified repository.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Sweagentd::SweagentdAPI::V1::ResolveUserIDToDisplayLoginResponse, or a Twirp::Error.
        sig do
          params(
            req: MonolithTwirp::Sweagentd::SweagentdAPI::V1::ResolveUserIDToDisplayLoginRequest,
            env: T::Hash[T.untyped, T.untyped], # rubocop:disable Sorbet/ForbidTUntyped
          ).returns(
            T.any(
              MonolithTwirp::Sweagentd::SweagentdAPI::V1::ResolveUserIDToDisplayLoginResponse,
              Twirp::Error,
            )
          )
        end
        def resolve_user_i_d_to_display_login(req, env)
          GitHub.tracer.in_span("sweagentd.twirp.resolve_user_i_d_to_display_login", kind: :internal) do
            GitHub.dogstats.distribution_time("sweagentd.twirp.resolve_user_i_d_to_display_login") do
              return Twirp::Error.invalid_argument("missing user_id", argument: "user_id") if req.user_id.zero?

              user = User.find_by(id: req.user_id)
              return Twirp::Error.not_found("user does not exist", argument: "user_id") if user.nil?

              MonolithTwirp::Sweagentd::SweagentdAPI::V1::ResolveUserIDToDisplayLoginResponse.new({
                display_login: user.display_login
              })
            end
          end
        end

        # Public: Implementation of the authorize_custom_agent_repo_for_user
        #
        # req - The Twirp request as a MonolithTwirp::Sweagentd::SweagentdAPI::V1::AuthorizeCustomAgentRepoForUserRequest
        # env - The Twirp environment as a Hash.
        #
        # Checks if the user can see custom agents for a given user, repo
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Sweagentd::SweagentdAPI::V1::AuthorizeCustomAgentRepoForUserResponse or a Twirp::Error.
        sig do
          params(
            req: MonolithTwirp::Sweagentd::SweagentdAPI::V1::AuthorizeCustomAgentRepoForUserRequest,
            env: T::Hash[T.untyped, T.untyped], # rubocop:disable Sorbet/ForbidTUntyped
          ).returns(
            T.any(
              MonolithTwirp::Sweagentd::SweagentdAPI::V1::AuthorizeCustomAgentRepoForUserResponse,
              Twirp::Error,
            )
          )
        end
        def authorize_custom_agent_repo_for_user(req, env)
          GitHub.tracer.in_span("sweagentd.twirp.authorize_custom_agent_for_user", kind: :internal) do
            GitHub.dogstats.distribution_time("sweagentd.twirp.authorize_custom_agent_for_user") do
              return Twirp::Error.invalid_argument("missing user_id", argument: "user_id") if req.user_id.zero?
              return Twirp::Error.invalid_argument("missing repository_id", argument: "repository_id") if req.repository_id.zero?

              user = User.find_by(id: req.user_id)
              return Twirp::Error.not_found("user does not exist", argument: "user_id") if user.nil?

              repo = Repository.find_by(id: req.repository_id)
              return Twirp::Error.not_found("repo does not exist") if repo.nil?

              MonolithTwirp::Sweagentd::SweagentdAPI::V1::AuthorizeCustomAgentRepoForUserResponse.new({
                can_access: repo_custom_agents_accessible_by_user?(repo, user)
              })
            end
          end
        end

        # Public: Implementation of the is_bypass_actor Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Sweagentd::SweagentdAPI::V1::IsBypassActorRequest.
        # env - The Twirp environment as a Hash.
        #
        # Checks if the specified actor is configured as a bypass actor for any active ruleset
        # in the repository. Works with any actor type (GitHub Apps, teams, users, etc.).
        #
        # Returns the Twirp response as a MonolithTwirp::Sweagentd::SweagentdAPI::V1::IsBypassActorResponse, or a Twirp::Error.
        sig do
          params(
            req: MonolithTwirp::Sweagentd::SweagentdAPI::V1::IsBypassActorRequest,
            env: T::Hash[T.untyped, T.untyped], # rubocop:disable Sorbet/ForbidTUntyped
          ).returns(
            T.any(
              MonolithTwirp::Sweagentd::SweagentdAPI::V1::IsBypassActorResponse,
              Twirp::Error,
            )
          )
        end
        def is_bypass_actor(req, env)
          GitHub.tracer.in_span("sweagentd.twirp.is_bypass_actor", kind: :internal) do
            GitHub.dogstats.distribution_time("sweagentd.twirp.is_bypass_actor") do
              return Twirp::Error.invalid_argument("Repository ID is required.", argument: "repository_id") if req["repository_id"].blank? || req["repository_id"].zero?
              return Twirp::Error.invalid_argument("Actor ID is required.", argument: "actor_id") if req["actor_id"].blank? || req["actor_id"].zero?

              repository = Repository.find_by(id: req["repository_id"])
              return Twirp::Error.not_found("Repository ID '#{req["repository_id"]}' not found.") unless repository

              actor_id = req["actor_id"]

              # Load all rulesets for this repository, including inherited org/enterprise rulesets.
              # Skip condition checking to check all rulesets regardless of whether their conditions currently match.
              # Filter to only enabled rulesets to avoid processing unnecessary data.
              all_rulesets = RepositoryRuleset.load_for(
                source: repository,
                include_parents: true,
                check_conditions_on_parent_rulesets: false
              )
              enabled_rulesets = all_rulesets.reject(&:disabled?)

              # Eager load bypass_actors to avoid N+1 queries
              ActiveRecord::Associations::Preloader.new(records: enabled_rulesets, associations: :bypass_actors).call

              # Build granular response with bypassable rulesets
              bypassable_rulesets = []
              enabled_rulesets.each do |ruleset|
                matching_bypass_actors = ruleset.bypass_actors.select { |bypass_actor| bypass_actor.actor_id == actor_id }

                matching_bypass_actors.each do |bypass_actor|
                  bypassable_rulesets << MonolithTwirp::Sweagentd::SweagentdAPI::V1::BypassableRuleset.new(
                    ruleset_id: ruleset.id,
                    ruleset_name: ruleset.name.present? ? ruleset.name : "Unnamed Ruleset",
                    bypass_mode: convert_bypass_mode_to_proto(bypass_actor.bypass_mode)
                  )
                end
              end

              # Create response and explicitly initialize all fields to avoid protobuf omitting defaults
              response = MonolithTwirp::Sweagentd::SweagentdAPI::V1::IsBypassActorResponse.new
              response.is_bypass_actor = bypassable_rulesets.any?

              # For protobuf repeated fields, add elements one by one
              bypassable_rulesets.each do |ruleset|
                response.rulesets << ruleset
              end

              return response
            end
          end
        end

        # Public: Implementation of the enterprise_agents Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Sweagentd::SweagentdAPI::V1::EnterpriseAgentsRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response with the repository ID containing the custom agent definitions.
        sig do
          params(
            req: MonolithTwirp::Sweagentd::SweagentdAPI::V1::EnterpriseAgentsRequest,
            env: T::Hash[T.untyped, T.untyped], # rubocop:disable Sorbet/ForbidTUntyped
          ).returns(
            T.any(
              MonolithTwirp::Sweagentd::SweagentdAPI::V1::EnterpriseAgentsResponse,
              Twirp::Error,
            )
          )
        end
        def enterprise_agents(req, env)
          GitHub.tracer.in_span("sweagentd.twirp.enterprise_agents", kind: :internal) do
            GitHub.dogstats.distribution_time("sweagentd.twirp.enterprise_agents") do
              return Twirp::Error.invalid_argument("missing user_id", argument: "user_id") if req.user_id.zero?
              return Twirp::Error.invalid_argument("missing repository_id", argument: "repository_id") if req.repository_id.zero?

              user = User.find_by(id: req.user_id)
              return Twirp::Error.not_found("user does not exist", argument: "user_id") if user.nil?

              repository = Repository.find_by(id: req.repository_id)
              return Twirp::Error.not_found("repository does not exist", argument: "repository_id") if repository.nil?

              repo_owner = repository.owner

              biz = case repo_owner
              when Organization
                repo_owner.business
              when User
                repo_owner.enterprise_managed_business
              end

              if biz.present? && !FeatureFlag.vexi.enabled?(:enterprise_ai_controls, biz, default: false)
                return Twirp::Error.not_found("enterprise not opted into Agent Control Plane feature")
              end

              if biz.nil?
                return Twirp::Error.not_found("enterprise not found for repository owner", argument: "repository_id")
              end

              MonolithTwirp::Sweagentd::SweagentdAPI::V1::EnterpriseAgentsResponse.new(
                repository_id: biz.subagent_definitions_source_repository_id
              )
            end
          end
        end

        # Public: Implementation of the get_issue_by_id Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Sweagentd::SweagentdAPI::V1::GetIssueByIdRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Sweagentd::SweagentdAPI::V1::GetIssueByIdResponse, or a Twirp::Error.
        sig do
          params(
            req: MonolithTwirp::Sweagentd::SweagentdAPI::V1::GetIssueByIdRequest,
            env: T::Hash[T.untyped, T.untyped], # rubocop:disable Sorbet/ForbidTUntyped
          ).returns(
            T.any(
              MonolithTwirp::Sweagentd::SweagentdAPI::V1::GetIssueByIdResponse,
              Twirp::Error,
            )
          )
        end
        def get_issue_by_id(req, env)
          GitHub.tracer.in_span("sweagentd.twirp.get_issue_by_id", kind: :internal) do
            GitHub.dogstats.distribution_time("sweagentd.twirp.get_issue_by_id") do
              return Twirp::Error.invalid_argument("Issue ID is required.", argument: "issue_id") if req.issue_id.blank? || req.issue_id.zero?

              issue = Issue.includes(:labels, :repository).find_by(id: req.issue_id)  # domain-isolation-query-violation:ignore:packages/issues (SELECT)
              return Twirp::Error.not_found("Issue ID '#{req.issue_id}' not found.") if issue.nil?

              MonolithTwirp::Sweagentd::SweagentdAPI::V1::GetIssueByIdResponse.new({
                issue: MonolithTwirp::Sweagentd::SweagentdAPI::V1::Issue.new({
                  id: issue.id,
                  number: issue.number,
                  title: issue.title,
                  body: issue.body,
                  state: issue.state,
                  repository_id: issue.repository_id,
                  repository_nwo: issue.repository&.name_with_display_owner,
                  html_url: issue.permalink,
                  author_id: issue.user_id,
                  created_at: issue.created_at&.to_i,
                  updated_at: issue.updated_at&.to_i,
                  labels: issue.labels.pluck(:name),
                })
              })
            end
          end
        end

        private

        sig do
          params(agent_id: T.nilable(Integer)).returns(T.nilable(::AgenticApp::AgentInstance))
        end
        def agent_for_bot_id_or_default(agent_id)
          return AgenticApp::CopilotAgent.instance if agent_id.nil? || agent_id == 0

          integration = Integration.find(agent_id)

          AgenticApp.agent_for_bot_id(integration.bot_id)
        end

        sig do
          params(
            agent: ::AgenticApp::AgentInstance,
            integration: Integration,
            repository: Repository,
          ).returns(T.nilable(User))
        end
        def agent_bot_for_repository(agent, integration, repository)
          owner = repository.owner
          return nil if owner.nil?

          if agent.global?
            result = ActiveRecord::Base.connected_to(role: :writing) do
              SiteScopedIntegrationInstallation::Creator.perform(
                integration,
                owner,
                repositories: [repository],
                entry_point: :twirp_api_sweagentd_create_pull_request,
              )
            end

            return nil unless result.success?

            installation = result.installation
            return nil unless installation

            return installation.bot
          end

          installation = IntegrationInstallation.with_repository(repository).find_by(integration: integration)
          installation&.bot
        end

        sig do
          params(
            repo: Repository,
            user: User,
          ).returns(T::Boolean)
        end
        def repo_custom_agents_accessible_by_user?(repo, user)
          # check if the user can see this repo
          return true if repo.readable_by?(user)

          # if it's a .github or .github-private repo, check if the user is a member of the owner org
          if repo.name == ".github" || repo.name == ".github-private"
            # if the repo is either a .github or .github-private repo, check if the owner of this repo
            # is an org of the user
            return user.organizations.include?(repo.owner)
          end

          # check for enterprise membership
          enterprise = get_enterprise_for_repo(repo)
          return false if enterprise.nil?

          # is the repo the one configured in the enterprise for subagent definitions?
          return false if enterprise.subagent_definitions_source_repository_id != repo.id

          org_for_enterprise = user.organizations.find do |org|
            org.business == enterprise || org.enterprise_managed_business == enterprise
          end

          # is user in an org that belongs to the same enterprise as the repo owner?
          org_for_enterprise.present?
        end

        sig do
          params(repo: Repository).returns(T.nilable(Business))
        end
        def get_enterprise_for_repo(repo)
          case repo.owner
          when Organization
            repo.owner&.business
          when User
            repo.owner&.enterprise_managed_business
          end
        end

        sig { returns(Integration) }
        memoize def integration
          ::Apps::Privileged.integration(:copilot_swe_agent)
        end

        # Helper method to convert database bypass mode to protobuf enum
        sig { params(db_mode: Integer).returns(Integer) }
        def convert_bypass_mode_to_proto(db_mode)
          case db_mode
          when RepositoryRulesetBypassActor::BYPASS_MODES[:any]
            MonolithTwirp::Sweagentd::SweagentdAPI::V1::BypassMode::BYPASS_MODE_ANY
          when RepositoryRulesetBypassActor::BYPASS_MODES[:pull_request]
            MonolithTwirp::Sweagentd::SweagentdAPI::V1::BypassMode::BYPASS_MODE_PULL_REQUEST
          when RepositoryRulesetBypassActor::BYPASS_MODES[:exempt]
            MonolithTwirp::Sweagentd::SweagentdAPI::V1::BypassMode::BYPASS_MODE_EXEMPT
          else
            MonolithTwirp::Sweagentd::SweagentdAPI::V1::BypassMode::BYPASS_MODE_INVALID
          end
        end
      end
    end
  end
end
