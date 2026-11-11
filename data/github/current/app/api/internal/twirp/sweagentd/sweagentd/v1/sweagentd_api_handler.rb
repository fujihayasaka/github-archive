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
          copilot_api
        ]
        handles_service MonolithTwirp::Sweagentd::SweagentdAPI::V1::SweagentdAPIService
        connected_to_writing_for :create_pull_request, :revoke_tokens

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

              # Map the snippy policy to a blocking mode for the agent to enforce
              copilot_user = Copilot::User.new(user)
              snippy_value = Copilot::Policies::Snippy.effective_value(copilot_user)
              response_params[:snippy_blocking_mode] = snippy_value_to_blocking_mode(snippy_value)

              # Materialize combined firewall rules from enterprise, org, and repo levels.
              if FeatureFlag.vexi.enabled?(:sweagentd_firewall_rules_in_config, repository, default: false)
                materialized = CopilotSweAgent::FirewallMaterializer.materialize(repository, user)
                response_params[:is_firewall_enabled] = materialized[:enabled]
                response_params[:should_firewall_use_default_rules] = materialized[:use_default_rules]
                response_params[:firewall_allowed_rules] = materialized[:rules]
              end
              # Populate validation tool settings from the repository's swe agent configuration.
              # Defaults to true (all tools enabled) when no config exists.
              swe_config = Copilot::SweAgentConfiguration.find_by(resource: repository)
              response_params[:use_codeql] = swe_config&.use_codeql != false
              response_params[:use_ccr] = swe_config&.use_ccr != false
              response_params[:use_secret_scanning] = swe_config&.use_secret_scanning != false
              response_params[:use_dependency_vuln_checks] = swe_config&.use_dependency_vuln_checks != false

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
              return Twirp::Error.invalid_argument("repository_id must be provided", argument: "repository_id") unless req.repository_id.present? && req.repository_id > 0
              return Twirp::Error.invalid_argument("head_branch_name must be provided", argument: "head_branch_name") unless req.head_branch_name.present?
              return Twirp::Error.invalid_argument("pr_name must be provided", argument: "pr_name") unless req.pr_name.present?
              return Twirp::Error.invalid_argument("pr_description must be provided", argument: "pr_description") unless req.pr_description.present?
              return Twirp::Error.invalid_argument("attribution_user_id must be provided", argument: "attribution_user_id") unless req.attribution_user_id.present?
              return Twirp::Error.invalid_argument("draft must be provided", argument: "draft") if req.draft.nil?

              repository = ::Repositories::Public.find_active(req.repository_id)
              return Twirp::Error.not_found("repository not found") if repository.nil?

              attribution_user = User.find_by(id: req.attribution_user_id)
              return Twirp::Error.not_found("user does not exist", argument: "attribution_user_id") if attribution_user.nil?
              return Twirp::Error.permission_denied("pull requests are disabled for this repository") unless PullRequestActivationConfig.new(repository).pull_requests_enabled?
              return Twirp::Error.permission_denied("pull request creation is not allowed for this user") unless PullRequestCreationConfig.new(repository).pull_request_creation_allowed_for?(attribution_user)

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

              # Determine if we should use performance optimizations for PR creation
              perf_hacks_enabled = FeatureFlag.vexi.enabled?(:coding_agent_create_pr_perf_hacks, repository, default: false)

              begin
                pr_opts = {
                  title: req.pr_name,
                  head: head_branch.name,
                  base: base_branch.name,
                  body: req.pr_description,
                  draft: req.draft,
                  user: agent_bot,
                  copilot_attributions: [attribution_user],
                  agent_session_id: req.session_id,
                }

                if perf_hacks_enabled
                  # Pre-build a comparison with branch names for refs, but pre-populate
                  # the resolved SHA instance variables to avoid git RPC calls during
                  # record_concrete_commit_points. This skips ref-to-SHA resolution since
                  # we already have the SHAs from head_branch and base_branch.
                  comparison = GitHub::Comparison.build(
                    base_repo: repository,
                    head_repo: repository,
                    base_revision: base_branch.name,
                    head_revision: head_branch.name,
                  )
                  # Pre-set resolved OIDs to skip async git RPC resolution
                  comparison.instance_variable_set(:@async_resolved_base_oid, base_branch.sha) # rubocop:disable GitHub/AvoidDynamicInstanceVariableMethods
                  comparison.instance_variable_set(:@async_resolved_head_oid, head_branch.sha) # rubocop:disable GitHub/AvoidDynamicInstanceVariableMethods
                  pr_opts[:comparison] = comparison
                end

                pull_request = PullRequest.create_for!(repository, pr_opts)
              rescue ActiveRecord::RecordInvalid => e
                # Check if the error is due to a uniqueness violation
                if e.record.errors.details.any? { |_, details| details.any? { |d| d[:error] == :duplicate } }
                  return Twirp::Error.already_exists("failed to create pull request: pull request already exists")
                end

                return Twirp::Error.invalid_argument("failed to create pull request: #{e.record.errors.full_messages.join(', ')}")
              end


              if perf_hacks_enabled
                # Create assignments directly to avoid expensive available_assignee_ids lookup
                # that happens in add_assignees/assignees=. Both agent_bot and attribution_user
                # are known-valid assignees (agent_bot from integration, attribution_user verified above).
                [agent_bot, attribution_user].each do |assignee|
                  Assignment.create!(
                    issue: pull_request.issue,
                    assignee: assignee,
                    skip_ensure_assignee_is_a_collaborator: true, # domain-isolation-query-violation:ignore:packages/issues (INSERT)
                  )
                end
              else
                pull_request.issue.add_assignees([agent_bot, attribution_user]) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
              end

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

              # Use custom permissions if provided, otherwise use defaults
              permissions = build_user_permissions_from_request(req.permissions)

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
                  permissions: permissions,
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

        # Public: Implementation of the mint_server_to_server_token_for_repo Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Sweagentd::SweagentdAPI::V1::MintServerToServerTokenForRepoRequest.
        # env - The Twirp environment as a Hash.
        #
        # Mints a server to server token for the specified repository without requiring a user.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Sweagentd::SweagentdAPI::V1::MintServerToServerTokenForRepoResponse, or a Twirp::Error.
        sig do
          params(
            req: MonolithTwirp::Sweagentd::SweagentdAPI::V1::MintServerToServerTokenForRepoRequest,
            env: T::Hash[T.untyped, T.untyped], # rubocop:disable Sorbet/ForbidTUntyped
          ).returns(
            T.any(
              MonolithTwirp::Sweagentd::SweagentdAPI::V1::MintServerToServerTokenForRepoResponse,
              Twirp::Error,
            )
          )
        end
        def mint_server_to_server_token_for_repo(req, env)
          GitHub.tracer.in_span("sweagentd.twirp.mint_server_to_server_token_for_repo", kind: :internal) do
            GitHub.dogstats.distribution_time("sweagentd.twirp.mint_server_to_server_token_for_repo") do
              return Twirp::Error.invalid_argument("missing repository_id", argument: "repository_id") unless req.repository_id.present? && req.repository_id > 0

              repository = ::Repositories::Public.find_active(req.repository_id)
              return Twirp::Error.not_found("repository does not exist", argument: "repository_id") if repository.nil?

              repo_owner = repository.owner
              return Twirp::Error.not_found("repository owner does not exist") if repo_owner.nil?

              agent = AgenticApp::CopilotAgent.instance
              if FeatureFlag.vexi.enabled?(:agenthq_mint_token, repository, default: false)
                return Twirp::Error.invalid_argument("unknown agent id", argument: "agent_id") if req.agent_id.blank?
                agent = agent_for_bot_id_or_default(req.agent_id)
                return Twirp::Error.invalid_argument("agent not found", argument: "agent_id") if agent.nil?
              end

              integration = agent.integration
              return Twirp::Error.failed_precondition("agent integration is not configured") if integration.nil?

              # Fall back to the integration's default permissions when none provided.
              permissions = build_server_permissions_from_request(req.permissions)
              if permissions.empty?
                permissions = integration.default_permissions.dup
              end

              redis_with_mysql_fallback = ServerToServerTokens.domain.redis_with_mysql_fallback?([
                integration, repo_owner
              ])

              # create site scoped installation for global apps
              if agent.global?
                # Need to be in a writing role to update records with the scoped installation
                ActiveRecord::Base.connected_to(role: :writing) do
                  result = SiteScopedIntegrationInstallation::Creator.perform_with_cache(
                    integration,
                    repo_owner,
                    repositories: [repository],
                    permissions: permissions,
                    entry_point: :twirp_api_sweagentd_mint_server_to_server_token,
                  )
                  return Twirp::Error.failed_precondition(
                    "could not create site scoped installation: #{result.error} " \
                    "(integration_id=#{integration&.id}, repo_owner_id=#{repo_owner.id}, repository_id=#{repository.id})"
                   ) unless result.success?

                  installation = result.installation
                  token_result = installation.generate_token(redis_with_mysql_fallback: redis_with_mysql_fallback)
                  return Twirp::Error.failed_precondition(
                    "could not generate token from site scoped installation: #{token_result.error} " \
                    "(integration_id=#{integration&.id}, repo_owner_id=#{repo_owner.id}, repository_id=#{repository.id})"
                  ) unless token_result.ok?

                  return MonolithTwirp::Sweagentd::SweagentdAPI::V1::MintServerToServerTokenForRepoResponse.new({
                    token: token_result.value.token_value
                  })
                end
              end

              # create scoped installation for non-global apps
              installation = IntegrationInstallation.with_target(repo_owner).find_by(integration: integration)
              if installation.nil?
                return Twirp::Error.failed_precondition(
                  "no installation found, cannot create scoped installation " \
                  "(integration_id=#{integration&.id}, repo_owner_id=#{repo_owner.id}, repository_id=#{repository.id})"
                )
              end

              # Need to be in a writing role to update records with the scoped installation
              ActiveRecord::Base.connected_to(role: :writing) do
                # Create a scoped installation for the specific repository
                scoped_result = ScopedIntegrationInstallation::Creator.perform_with_cache(
                  installation,
                  repositories: [repository],
                  permissions: permissions,
                  entry_point: :twirp_api_sweagentd_mint_server_to_server_token,
                )

                if scoped_result.failed?
                  return Twirp::Error.failed_precondition(
                    "could not create scoped installation: #{scoped_result.error} " \
                    "(integration_id=#{integration&.id}, repo_owner_id=#{repo_owner.id}, repository_id=#{repository.id})"
                  )
                end

                scoped_installation = scoped_result.installation
                token_result = scoped_installation.generate_token(redis_with_mysql_fallback: redis_with_mysql_fallback)
                return Twirp::Error.failed_precondition(
                  "could not generate token from scoped installation: #{token_result.error} " \
                  "(integration_id=#{integration&.id}, repo_owner_id=#{repo_owner.id}, repository_id=#{repository.id})"
                ) unless token_result.ok?

                MonolithTwirp::Sweagentd::SweagentdAPI::V1::MintServerToServerTokenForRepoResponse.new({
                  token: token_result.value.token_value
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
              return Twirp::Error.invalid_argument("Organization ID is required.", argument: "organization_id") if req["organization_id"].blank? || req["organization_id"] <= 0

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
              return Twirp::Error.invalid_argument("missing user_id", argument: "user_id") if req.user_id <= 0

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
              return Twirp::Error.invalid_argument("missing user_id", argument: "user_id") if req.user_id <= 0
              return Twirp::Error.invalid_argument("missing repository_id", argument: "repository_id") if req.repository_id <= 0

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
              return Twirp::Error.invalid_argument("Repository ID is required.", argument: "repository_id") if req["repository_id"].blank? || req["repository_id"] <= 0
              return Twirp::Error.invalid_argument("Actor ID is required.", argument: "actor_id") if req["actor_id"].blank? || req["actor_id"] <= 0

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
              # user_id is deprecated and ignored

              # Check if new fields exist and have values (for backward compatibility)
              owner_id = req.respond_to?(:owner_id) ? req.owner_id : 0
              owner_name = req.respond_to?(:owner_name) ? req.owner_name.to_s : ""

              # At least one of repository_id, owner_id, or owner_name must be provided
              if req.repository_id <= 0 && owner_id <= 0 && owner_name.empty?
                return Twirp::Error.invalid_argument("missing repository_id, owner_id, or owner_name", argument: "find_agents_by")
              end

              # Determine the owner from either repository_id, owner_id, or owner_name
              repo_owner = if req.repository_id > 0
                repository = Repository.find_by(id: req.repository_id)
                return Twirp::Error.not_found("repository does not exist", argument: "repository_id") if repository.nil?
                repository.owner
              elsif owner_id > 0
                # Try to find owner as either User or Organization
                owner = User.find_by(id: owner_id) || Organization.find_by(id: owner_id)
                return Twirp::Error.not_found("owner does not exist", argument: "owner_id") if owner.nil?
                owner
              elsif !owner_name.empty?
                # Try to find owner by name as either User or Organization
                owner = User.find_by(login: owner_name) || Organization.find_by(login: owner_name)
                return Twirp::Error.not_found("owner does not exist", argument: "owner_name") if owner.nil?
                owner
              end

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
              return Twirp::Error.invalid_argument("Issue ID is required.", argument: "issue_id") if req.issue_id.blank? || req.issue_id <= 0

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

        # Public: Implementation of the get_agentic_apps Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Sweagentd::SweagentdAPI::V1::GetAgenticAppsRequest,
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirpd::Sweagentd::SweagentdAPI::V1::GetAgenticAppsResponse, or a Twirp::Error.
        sig do
          params(
            req: MonolithTwirp::Sweagentd::SweagentdAPI::V1::GetAgenticAppsRequest,
            env: T::Hash[T.untyped, T.untyped], # rubocop:disable Sorbet/ForbidTUntyped
          ).returns(
            T.any(
              MonolithTwirp::Sweagentd::SweagentdAPI::V1::GetAgenticAppsResponse,
              Twirp::Error,
            )
          )
        end
        def get_agentic_apps(req, env)
          GitHub.tracer.in_span("sweagentd.twirp.get_agentic_apps", kind: :internal) do
            GitHub.dogstats.distribution_time("sweagentd.twirp.get_agentic_apps") do
              agents = ::AgenticApp.all_agents
              apps = []

              agents.each do |agent|
                integration = agent.integration
                next unless integration
                bot = integration&.bot
                next unless bot

                has_source = false
                source_url = ""
                if agent.is_a?(AgenticApp::ThirdPartyAgent)
                  has_source = true
                  source_url = agent.repository_url
                end

                apps << MonolithTwirp::Sweagentd::SweagentdAPI::V1::AgenticApp.new(
                  app_id: integration.id,
                  app_login: agent.slug,
                  app_bot_id: agent.bot_id,
                  bot_login: bot.login,
                  commit_login: bot.login,
                  commit_email: agent.commit_email,
                  has_source: has_source,
                  source_url: source_url
                )
              end

              MonolithTwirp::Sweagentd::SweagentdAPI::V1::GetAgenticAppsResponse.new(
                agentic_apps: apps,
              )
            end
          end
        end

        # Public: Implementation of the sign_commit Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Sweagentd::SweagentdAPI::V1::SignCommitRequest.
        # env - The Twirp environment as a Hash.
        #
        # Signs a commit payload for the specified repository and agent.
        #
        # Returns the Twirp response as a MonolithTwirp::Sweagentd::SweagentdAPI::V1::SignCommitResponse, or a Twirp::Error.
        sig do
          params(
            req: MonolithTwirp::Sweagentd::SweagentdAPI::V1::SignCommitRequest,
            env: T::Hash[T.untyped, T.untyped], # rubocop:disable Sorbet/ForbidTUntyped
          ).returns(
            T.any(
              MonolithTwirp::Sweagentd::SweagentdAPI::V1::SignCommitResponse,
              Twirp::Error,
            )
          )
        end
        def sign_commit(req, env)
          GitHub.tracer.in_span("sweagentd.twirp.sign_commit", kind: :internal) do
            GitHub.dogstats.distribution_time("sweagentd.twirp.sign_commit") do
              repository = ::Repositories::Public.find_active(req.repository_id)
              return Twirp::Error.not_found("repository does not exist", argument: "repository_id") if repository.nil?

              attribution_user = User.find_by(id: req.attribution_user_id)
              return Twirp::Error.not_found("user does not exist", argument: "attribution_user_id") if attribution_user.nil?

              agent = agent_for_bot_id_or_default(req.agent_id)
              return Twirp::Error.not_found("agent not found", argument: "agent_id") if agent.nil?

              unless agent.global?
                unless agent.enabled_for_repository?(repository, attribution_user)
                  return Twirp::Error.permission_denied("agent not enabled for repository")
                end
              end

              unless repository.pushable_by?(attribution_user)
                return Twirp::Error.permission_denied("user does not have push access to this repository")
              end

              committer_email = extract_committer_email(req.payload)
              unless committer_email.present? && GitHub.web_committer_email?(committer_email)
                return Twirp::Error.invalid_argument(
                  "invalid committer email in payload for signature verification",
                  argument: "payload",
                )
              end

              GitHub.logger.info(
                "Signing commit for sweagentd",
                "code.namespace": self.class.name,
                "code.function": env[:rpc_method],
                "gh.repo.id": repository.id,
                "gh.sweagentd.attributed_user_id": attribution_user.id,
                "gh.sweagentd.agent_id": req.agent_id,
              )

              signature = repository.sign_commit(req.payload)
              return Twirp::Error.failed_precondition("commit signing is not available") if signature.nil?

              MonolithTwirp::Sweagentd::SweagentdAPI::V1::SignCommitResponse.new(
                signature: signature,
              )
            end
          end
        end

        # Public: Implementation of the revoke_tokens Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Sweagentd.SweagentdAPI::V1::RevokeTokensRequest.
        # env - The Twirp environment as a Hash.
        #
        # Revokes tokens issued by the SWE Agent.
        # Returns the Twirp response as a MonolithTwirp::Sweagentd::SweagentdAPI::V1::RevokeTokensResponse, or a Twirp::Error.
        sig do
          params(
            req: MonolithTwirp::Sweagentd::SweagentdAPI::V1::RevokeTokensRequest,
            env: T::Hash[T.untyped, T.untyped], # rubocop:disable Sorbet/ForbidTUntyped
          ).returns(
            T.any(
              MonolithTwirp::Sweagentd::SweagentdAPI::V1::RevokeTokensResponse,
              Twirp::Error,
            )
          )
        end
        def revoke_tokens(req, env)
          GitHub.tracer.in_span("sweagentd.twirp.revoke_tokens", kind: :internal) do
            GitHub.dogstats.distribution_time("sweagentd.twirp.revoke_tokens") do
              return Twirp::Error.invalid_argument("missing agent_id", argument: "agent_id") if req.agent_id.nil? || req.agent_id <= 0
              return Twirp::Error.invalid_argument("missing tokens", argument: "tokens") if req.tokens.empty?

              agent = agent_for_bot_id_or_default(req.agent_id)
              return Twirp::Error.not_found("Agent not found with agent_id '#{req.agent_id}'.") if !agent

              app = agent.integration

              total_revoked = 0
              failed_tokens = []

              req.tokens.each do |token|
                if token.start_with?(ServerToServerTokens::Domain::ACCESS_TOKEN_PREFIX)
                  auth_token = ServerToServerTokens.domain.by_unhashed_token(token)
                  # Validate that the token belongs to the requested agent's integration
                  if auth_token && token_belongs_to_integration?(auth_token, app.id)
                    target =
                      ActiveRecord::Base.connected_to(role: :reading) do
                        auth_token.authenticatable&.target
                      end

                    result =
                      if ServerToServerTokens.domain.redis_with_mysql_fallback?([app, target])
                        ServerToServerTokens.domain.destroy_by_hashed_token_redis_with_mysql_fallback(auth_token.hashed_value)
                      else
                        ServerToServerTokens.domain.destroy_by_hashed_token(auth_token.hashed_value)
                      end
                    if result.ok?
                      total_revoked += 1
                    else
                      failed_tokens << token
                    end
                  else
                    failed_tokens << token
                  end
                else
                  access = app.accesses.with_active_token(token)
                  if access&.destroy_with_explanation(:oauth_application, entry_point: :sweagentd_api_revoke_tokens)
                    total_revoked += 1
                  else
                    failed_tokens << token
                  end
                end
              end

              MonolithTwirp::Sweagentd::SweagentdAPI::V1::RevokeTokensResponse.new(
                total_revoked: total_revoked,
                failed_tokens: failed_tokens,
              )
            end
          end
        end

        private

        COMMIT_COMMITTER_REGEX = /\Acommitter [^<]*<(.+)>/
        private_constant :COMMIT_COMMITTER_REGEX

        # Extracts the committer email from a commit payload string.
        #
        # payload - The String commit body (e.g. "tree ...\ncommitter Name <email> ...").
        #
        # Returns the committer email String, or nil if not found.
        sig { params(payload: String).returns(T.nilable(String)) }
        def extract_committer_email(payload)
          payload.each_line do |line|
            break if line.strip.empty?
            if match = line.match(COMMIT_COMMITTER_REGEX)
              return match[1]
            end
          end
          nil
        end

        # Default permissions for user-to-server token minting
        DEFAULT_USER_TOKEN_PERMISSIONS = T.let({
          "metadata" => :read,
          "contents" => :write,
          "pull_requests" => :read,
        }.freeze, T::Hash[String, Symbol])

        # Builds permissions hash from request for user-to-server tokens.
        # Uses limited default permissions when none provided.
        sig do
          params(
            request_permissions: T.nilable(T.any(T.untyped, T::Hash[String, String]))
          ).returns(T::Hash[String, Symbol])
        end
        def build_user_permissions_from_request(request_permissions)
          # Convert to hash first since Google::Protobuf::Map doesn't have empty?
          # Handle nil case as well
          permissions_hash = request_permissions&.to_h || {}
          if permissions_hash.empty?
            DEFAULT_USER_TOKEN_PERMISSIONS.dup
          else
            permissions_hash.transform_values(&:to_sym)
          end
        end

        # Parses the permissions map from the request protobuf.
        # Returns empty hash if no custom permissions were provided.
        sig do
          params(
            request_permissions: T.nilable(T.any(T.untyped, T::Hash[String, String]))
          ).returns(T::Hash[String, Symbol])
        end
        def build_server_permissions_from_request(request_permissions)
          # Convert to hash first since Google::Protobuf::Map doesn't have empty?
          # Handle nil case as well
          permissions_hash = request_permissions&.to_h || {}
          if permissions_hash.empty?
            {}
          else
            permissions_hash.transform_values(&:to_sym)
          end
        end

        # Returns the AgenticApp::AgentInstance for the given agent_id (Integration ID),
        # or the default Copilot agent if agent_id is nil or 0.
        # Returns nil if the agent_id does not correspond to a valid Integration.
        #
        # agent_id - The Integration ID of the agent.
        #
        # Returns the AgenticApp::AgentInstance or nil.
        sig do
          params(agent_id: T.nilable(Integer)).returns(T.nilable(::AgenticApp::AgentInstance))
        end
        def agent_for_bot_id_or_default(agent_id)
          return AgenticApp::CopilotAgent.instance if agent_id.nil? || agent_id == 0

          integration = Integration.find_by(id: agent_id)
          return nil unless integration

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

        # Checks if a server-to-server token belongs to a specific integration.
        # Uses authenticatable_type and authenticatable_id to look up the integration_id
        # without relying on the authenticatable association (which isn't in the interface).
        #
        # auth_token - The IAuthenticationToken to check.
        # integration_id - The Integration ID to match against.
        #
        # Returns true if the token belongs to the integration, false otherwise.
        sig { params(auth_token: ServerToServerTokens::IAuthenticationToken, integration_id: Integer).returns(T::Boolean) }
        def token_belongs_to_integration?(auth_token, integration_id)
          authenticatable_type = auth_token.authenticatable_type
          authenticatable_id = auth_token.authenticatable_id

          case authenticatable_type
          when "IntegrationInstallation"
            IntegrationInstallation.where(id: authenticatable_id, integration_id: integration_id).exists?
          when "ScopedIntegrationInstallation"
            # ScopedIntegrationInstallation gets integration through its parent IntegrationInstallation
            # Avoid cross-database join by getting parent_id first, then checking integration_id
            parent_id = ScopedIntegrationInstallation.where(id: authenticatable_id).pick(:integration_installation_id)
            return false if parent_id.nil?

            IntegrationInstallation.where(id: parent_id, integration_id: integration_id).exists?
          when "SiteScopedIntegrationInstallation"
            SiteScopedIntegrationInstallation.where(id: authenticatable_id, integration_id: integration_id).exists?
          else
            false
          end
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

        # Helper method to convert Snippy policy value to allowed or blocked blocking mode
        sig { params(snippy_value: String).returns(Integer) }
        def snippy_value_to_blocking_mode(snippy_value)
          config_values = Copilot::Policies::Snippy.config_values
          case snippy_value
          when config_values[:enabled]
            MonolithTwirp::Sweagentd::SweagentdAPI::V1::SnippyBlockingMode::SNIPPY_BLOCKING_MODE_BLOCKED
          else
            MonolithTwirp::Sweagentd::SweagentdAPI::V1::SnippyBlockingMode::SNIPPY_BLOCKING_MODE_ALLOWED
          end
        end
      end
    end
  end
end
