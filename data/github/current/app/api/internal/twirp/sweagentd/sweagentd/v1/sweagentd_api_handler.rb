# typed: strict
# frozen_string_literal: true

require "monolith-twirp-sweagentd-sweagentd"

module Api::Internal::Twirp::Sweagentd
  module Sweagentd
    module V1
      # Handler for the MonolithTwirp::Sweagentd::Sweagentd::V1::SweagentdAPIService
      class SweagentdApiHandler < Api::Internal::Twirp::Handler
        include GitHub::Memoizer
        include Scientist

        sig do
          params(
            rack_env: T::Hash[T.untyped, T.untyped],
            env: T::Hash[T.untyped, T.untyped],
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
          copilot_mission_control
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
            env: T::Hash[T.untyped, T.untyped],
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

              is_mcp_enabled = if user.is_a?(::Organization)
                Copilot::Organization.new(user).mcp_enabled?
              else
                Copilot::Public::User.for(user).mcp_enabled?
              end

              return MonolithTwirp::Sweagentd::SweagentdAPI::V1::MCPConfigurationForRepositoryResponse.new(
                is_mcp_enabled: is_mcp_enabled,
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
            env: T::Hash[T.untyped, T.untyped],
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
                is_sweagentd_enabled: repository.copilot_swe_agent_enabled?(user),
              }

              if FeatureFlag.vexi.enabled?(:sweagent_send_sandbox_enabled, repository, default: false)
                response_params[:is_sandbox_enabled] = sandbox_policy_enabled_for_repository?(repository)
              end

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
              if FeatureFlag.vexi.enabled?(:sweagentd_firewall_rules_in_config, repository, repository.owner, user, default: false)
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

              # Surface whether repo admin has disabled agentic memory for this repo.
              # Only respect the persisted value when the feature flag is enabled; otherwise
              # return false so that rolling back the flag restores memory for all repos.
              # Defaults to false (memory enabled) when no config exists or not explicitly set.
              repo_memory_opt_out_enabled = FeatureFlag.vexi.enabled?(:copilot_repo_memory_opt_out, repository, default: false)
              response_params[:repo_memory_disabled] = repo_memory_opt_out_enabled && T.unsafe(swe_config)&.memory_disabled == true

              # Surface the effective automations-disabled policy (cascades from org → repo).
              response_params[:automations_disabled] = repository.copilot_swe_agent_automations_disabled?

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
            env: T::Hash[T.untyped, T.untyped],
          ).returns(
            T.any(
              T::Hash[T.untyped, T.untyped],
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
              pull_request_creation_config = PullRequestCreationConfig.new(repository)
              return Twirp::Error.permission_denied("pull request creation is not allowed for this user") unless pull_request_creation_config.pull_request_creation_allowed_for?(attribution_user)

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

              if FeatureFlag.vexi.enabled?(:pull_request_creation_cap, repository, default: false)
                pull_request = PullRequestCreationConfig::PullRequestAttributes.new(
                  user: agent_bot,
                  draft: req.draft,
                  pull_request_copilot_attributions: [
                    PullRequestCreationConfig::CopilotAttributionAttributes.new(user: attribution_user),
                  ],
                )
                return Twirp::Error.permission_denied("open pull request limit has been reached for this user") if pull_request_creation_config.pull_request_exceeds_limit?(pull_request)
              end

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

              maybe_group_into_stack(repository, pull_request, attribution_user)

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
            env: T::Hash[T.untyped, T.untyped],
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

                scoped_access, error = integration.convert_to_scoped_access(
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

        # Public: Implementation of the mint_user_to_server_token_for_repos Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Sweagentd::SweagentdAPI::V1::MintUserToServerTokenForReposRequest.
        # env - The Twirp environment as a Hash.
        #
        # Mints a user-to-server token scoped to zero or more repositories.
        # When repository_ids is empty, the token is scoped installation-wide
        # under scope_id (used by agent compute environments created without
        # a repository attached). When repository_ids is non-empty, all
        # repositories must share a single owner; that owner is used as the
        # installation target.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Sweagentd::SweagentdAPI::V1::MintUserToServerTokenForReposResponse, or a Twirp::Error.
        sig do
          params(
            req: MonolithTwirp::Sweagentd::SweagentdAPI::V1::MintUserToServerTokenForReposRequest,
            env: T::Hash[T.untyped, T.untyped],
          ).returns(
            T.any(
              MonolithTwirp::Sweagentd::SweagentdAPI::V1::MintUserToServerTokenForReposResponse,
              Twirp::Error,
            )
          )
        end
        def mint_user_to_server_token_for_repos(req, env)
          GitHub.tracer.in_span("sweagentd.twirp.mint_user_to_server_token_for_repos", kind: :internal) do
            GitHub.dogstats.distribution_time("sweagentd.twirp.mint_user_to_server_token_for_repos") do
              return Twirp::Error.invalid_argument("missing user_id", argument: "user_id") if req.user_id.blank?

              repo_scopes = req.repositories.to_a
              if repo_scopes.empty? && req.scope_id.blank?
                return Twirp::Error.invalid_argument("scope_id is required when repositories is empty", argument: "scope_id")
              end

              user = User.find_by(id: req.user_id)
              return Twirp::Error.not_found("user does not exist", argument: "user_id") if user.nil?

              repositories = []
              target = nil
              flag_subject = nil

              if repo_scopes.any?
                repository_ids = repo_scopes.map(&:repository_id)
                repositories = ::Repositories::Public.load_repositories(repository_ids).to_a
                if repositories.length != repository_ids.length
                  return Twirp::Error.not_found("repository does not exist", argument: "repositories")
                end

                owners = repositories.map(&:owner).uniq
                if owners.length != 1
                  return Twirp::Error.invalid_argument("all repositories must share a single owner", argument: "repositories")
                end

                target = owners.first
                return Twirp::Error.not_found("repository owner does not exist") if target.nil?

                flag_subject = repositories.first
              else
                target = User.find_by(id: req.scope_id) || Organization.find_by(id: req.scope_id)
                return Twirp::Error.not_found("scope does not exist", argument: "scope_id") if target.nil?

                flag_subject = target
              end

              agent = AgenticApp::CopilotAgent.instance
              if FeatureFlag.vexi.enabled?(:agenthq_mint_token, flag_subject, default: false)
                return Twirp::Error.invalid_argument("unknown agent id", argument: "agent_id") if req.agent_id.blank?
                agent = agent_for_bot_id_or_default(req.agent_id)
                return Twirp::Error.invalid_argument("agent not found", argument: "agent_id") if agent.nil?

                unless agent.global?
                  if repositories.any?
                    unless repositories.all? { |repo| agent.enabled_for_repository?(repo, user) }
                      return Twirp::Error.permission_denied("agent not enabled for repository")
                    end
                  end
                end
              end

              integration = agent.integration
              return Twirp::Error.failed_precondition("agent integration is not configured") if integration.nil?

              # When repositories are provided, use per-repo permissions from
              # RepositoryScope entries. When empty (installation-wide), use
              # the top-level permissions map.
              permissions = if repo_scopes.any?
                build_user_permissions_from_request(T.must(repo_scopes.first).permissions)
              else
                build_user_permissions_from_request(req.permissions)
              end

              # Need to be in a writing role to update records with the scoped installation
              ActiveRecord::Base.connected_to(role: :writing) do
                # Create a fresh access grant for the integration/user
                new_access = integration.grant(user)

                # Check if SAML would be enforced for this target and if so create a credential authorization grant for them.
                # This should be safe to do because all mechanisms to trigger this secret provider already go through appropriate SAML CAP filtering
                # either in the API or in the Rails controllers (ex: assigning an issue to Copilot).
                if target.organization? && Organization::SamlEnforcementPolicy.new(organization: target, user:).enforced?
                  if !Organization::CredentialAuthorization.by_organization_credential(organization: target, credential: new_access).active.exists?
                    authorization = Organization::CredentialAuthorization.grant(organization: target, credential: new_access, actor: user)
                    return Twirp::Error.permission_denied("Could not create credential authorization grant. Org: #{target.id}, user: #{user.id}") if authorization.nil?
                  end
                end

                # `nil` repository_ids means installation-wide (all repos in
                # the installation). A non-empty list scopes the token to
                # exactly those repositories.
                resource_repository_ids = repositories.any? ? repositories.map(&:id) : nil

                scoped_access, error = integration.convert_to_scoped_access(
                  new_access,
                  target,
                  permissions: permissions,
                  resources: {
                    repository_ids: resource_repository_ids,
                  },
                  entry_point: :twirp_api_copilot_swe_agent_api_handler,
                )
                if error
                  return Twirp::Error.permission_denied(error)
                end

                # Sets the expiration for the access and the installation without
                # needing to update all of the `permissions` rows.
                token, _ = scoped_access.redeem(extended_expiry: true)

                MonolithTwirp::Sweagentd::SweagentdAPI::V1::MintUserToServerTokenForReposResponse.new(token: token)
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
            env: T::Hash[T.untyped, T.untyped],
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
                    "could not create site scoped installation: #{result.error.try(:message) || result.error} " \
                    "(integration_id=#{integration&.id}, repo_owner_id=#{repo_owner.id}, repository_id=#{repository.id})"
                   ) unless result.success?

                  installation = result.installation
                  token_result = installation.generate_token(redis_with_mysql_fallback: redis_with_mysql_fallback)
                  return Twirp::Error.failed_precondition(
                    "could not generate token from site scoped installation: #{token_result.error.try(:message) || token_result.error} " \
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
                    "could not create scoped installation: #{scoped_result.error.try(:message) || scoped_result.error} " \
                    "(integration_id=#{integration&.id}, repo_owner_id=#{repo_owner.id}, repository_id=#{repository.id})"
                  )
                end

                scoped_installation = scoped_result.installation
                token_result = scoped_installation.generate_token(redis_with_mysql_fallback: redis_with_mysql_fallback)
                return Twirp::Error.failed_precondition(
                  "could not generate token from scoped installation: #{token_result.error.try(:message) || token_result.error} " \
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
            env: T::Hash[T.untyped, T.untyped],
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

        # Public: Implementation of the get_organization_c_c_a_runner_settings Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Sweagentd::SweagentdAPI::V1::GetOrganizationCCARunnerSettingsRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the organization's CCA runner settings (runner type, labels, group, and repo customization flag).
        #
        # Returns the Twirp response as a MonolithTwirp::Sweagentd::SweagentdAPI::V1::GetOrganizationCCARunnerSettingsResponse, or a Twirp::Error.
        sig do
          params(
            req: MonolithTwirp::Sweagentd::SweagentdAPI::V1::GetOrganizationCCARunnerSettingsRequest,
            env: T::Hash[T.untyped, T.untyped],
          ).returns(
            T.any(
              MonolithTwirp::Sweagentd::SweagentdAPI::V1::GetOrganizationCCARunnerSettingsResponse,
              Twirp::Error,
            )
          )
        end
        def get_organization_c_c_a_runner_settings(req, env)
          GitHub.tracer.in_span("sweagentd.twirp.get_organization_c_c_a_runner_settings", kind: :internal) do
            GitHub.dogstats.distribution_time("sweagentd.twirp.get_organization_c_c_a_runner_settings") do
              return Twirp::Error.invalid_argument("Organization ID is required.", argument: "organization_id") if req["organization_id"].blank? || req["organization_id"] <= 0

              organization = Organization.find_by(id: req["organization_id"])
              return Twirp::Error.not_found("Organization ID '#{req["organization_id"]}' not found.") if !organization

              return Twirp::Error.permission_denied("Runner control settings are not enabled for this organization.") unless FeatureFlag.vexi.enabled?(:copilot_swe_agent_runner_control_settings, organization, default: false)

              runner_type = organization.copilot_swe_agent_runner_type
              allow_repo_custom_runner = organization.copilot_swe_agent_allow_repo_custom_runner

              response = MonolithTwirp::Sweagentd::SweagentdAPI::V1::GetOrganizationCCARunnerSettingsResponse.new(
                allow_repository_customization: allow_repo_custom_runner,
              )

              case runner_type
              when Configurable::CopilotSweAgentRunner::RUNNER_TYPE_LABELED
                labels = organization.copilot_swe_agent_runner_labels.split(",").map(&:strip).reject(&:empty?)
                group_name = organization.copilot_swe_agent_runner_group_name

                labeled_runner = MonolithTwirp::Sweagentd::SweagentdAPI::V1::LabeledRunner.new(labels: labels)
                labeled_runner.group = group_name if group_name.present?

                response.labeled_runner = labeled_runner
              when Configurable::CopilotSweAgentRunner::RUNNER_TYPE_STANDARD
                response.standard_runner = Google::Protobuf::Empty.new
              else
                return Twirp::Error.internal("Unknown runner type '#{runner_type}' for organization '#{req["organization_id"]}'.")
              end

              response
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
            env: T::Hash[T.untyped, T.untyped],
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
            env: T::Hash[T.untyped, T.untyped],
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
            env: T::Hash[T.untyped, T.untyped],
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
              # TODO: this was migrated to match the existing behavior of RepositoryRuleset.load_for
              # but it feels like it is probably wrong. Do we want to load rulesets that don't apply or that are in evaluate mode?
              sources = %w[branch tag push repository].map do |target|
                Repositories.domain.rulesets.inherited_sources(repository, target)
              end
              sources = sources.flatten.uniq + [repository]
              all_rulesets = Repositories.domain.rulesets.load_rulesets_for_sources(sources, targets: %w[branch tag push repository])

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
            env: T::Hash[T.untyped, T.untyped],
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
            env: T::Hash[T.untyped, T.untyped],
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

              issue = Issue.includes(:labels, :repository).find_by(id: req.issue_id) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
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

        # Returns the combined org+repo trigger-actor policy for `req.repository_id`
        # under "least permissive wins": both layers must permit when an org is involved.
        sig do
          params(
            req: MonolithTwirp::Sweagentd::SweagentdAPI::V1::GetEffectiveTriggerActorPolicyRequest,
            env: T::Hash[T.untyped, T.untyped],
          ).returns(
            T.any(
              MonolithTwirp::Sweagentd::SweagentdAPI::V1::GetEffectiveTriggerActorPolicyResponse,
              Twirp::Error,
            )
          )
        end
        def get_effective_trigger_actor_policy(req, env)
          GitHub.tracer.in_span("sweagentd.twirp.get_effective_trigger_actor_policy", kind: :internal) do
            GitHub.dogstats.distribution_time("sweagentd.twirp.get_effective_trigger_actor_policy") do
              return Twirp::Error.invalid_argument("Repository ID is required.", argument: "repository_id") if req.repository_id.blank? || req.repository_id <= 0

              repository = ::Repositories::Public.find_active(req.repository_id)
              return Twirp::Error.not_found("Repository ID '#{req.repository_id}' not found.") if repository.nil?

              owner = repository.owner
              return Twirp::Error.not_found("Repository owner not found for repository ID '#{req.repository_id}'.") if owner.nil?

              # Sorbet knows Organization < User via STI, so a case/else would be flagged
              # unreachable; is_a? is the idiomatic check for User-owned vs Org-owned.
              org_allows = if owner.is_a?(::Organization)
                owner.copilot_swe_agent_allow_read_access_triggers_policy
              else
                true
              end
              repo_allows = repository.copilot_swe_agent_repo_allow_read_access_triggers_policy

              MonolithTwirp::Sweagentd::SweagentdAPI::V1::GetEffectiveTriggerActorPolicyResponse.new(
                allow_read_access_triggers: org_allows && repo_allows,
              )
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
            env: T::Hash[T.untyped, T.untyped],
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

                agent_source_res = if integration.agent_source.present?
                  source = integration.agent_source
                  MonolithTwirp::Sweagentd::SweagentdAPI::V1::AgentSource.new(
                    url: source.repository&.permalink.to_s,
                    sha: source.commit_oid,
                  )
                end

                app_args = {
                  app_id: integration.id,
                  app_login: agent.slug,
                  app_bot_id: agent.bot_id,
                  bot_login: bot.login,
                  commit_login: bot.login,
                  commit_email: agent.commit_email,
                  agent_source: agent_source_res,
                }

                if FeatureFlag.vexi.enabled?(:sweagentd_app_slug, default: false) &&
                    MonolithTwirp::Sweagentd::SweagentdAPI::V1::AgenticApp.descriptor.lookup("app_slug")
                  app_args[:app_slug] = agent.slug
                end

                if FeatureFlag.vexi.enabled?(:copilot_engine_sdk_model_selection, default: false) &&
                    MonolithTwirp::Sweagentd::SweagentdAPI::V1::AgenticApp.descriptor.lookup("model_vendors")
                  app_args[:model_vendors] = agent.model_vendors
                end

                apps << MonolithTwirp::Sweagentd::SweagentdAPI::V1::AgenticApp.new(**app_args)
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
            env: T::Hash[T.untyped, T.untyped],
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

              if attribution_user.organization?
                unless repository.owner_id == attribution_user.id
                  return Twirp::Error.permission_denied("organization is not the owner of this repository")
                end
              else
                unless repository.pushable_by?(attribution_user)
                  return Twirp::Error.permission_denied("user does not have push access to this repository")
                end
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
            env: T::Hash[T.untyped, T.untyped],
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
                      if ServerToServerTokens::Domain.stateless_token?(token)
                        ServerToServerTokens.domain.destroy_by_unhashed_token(token, reason: "sweagentd_token_revocation")
                      elsif ServerToServerTokens.domain.redis_with_mysql_fallback?([app, target])
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
                  access = science "oauth-access-active-for-application-sweagentd" do |e|
                    e.use { app.accesses.with_active_token(token) }
                    e.try do
                      OauthAccessTokens.domain.active_for_application(token,
                        application_type: app.class.name,
                        application_id: app.id,
                      )
                    end
                    e.clean { |value| value&.id }
                  end
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

        # Public: Implementation of the get_repository_installation Twirp RPC.
        #
        # Given a repository ID and agent ID (Integration ID), returns the
        # installation ID (if the app is installed on the repository), the
        # repository owner type, the app's client ID, whether the agent is
        # global, and the granted permissions for the installation.
        #
        # req - The Twirp request as a MonolithTwirp::Sweagentd::SweagentdAPI::V1::GetRepositoryInstallationRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a
        # MonolithTwirp::Sweagentd::SweagentdAPI::V1::GetRepositoryInstallationResponse, or a Twirp::Error.
        sig do
          params(
            req: MonolithTwirp::Sweagentd::SweagentdAPI::V1::GetRepositoryInstallationRequest,
            env: T::Hash[T.untyped, T.untyped],
          ).returns(
            T.any(
              MonolithTwirp::Sweagentd::SweagentdAPI::V1::GetRepositoryInstallationResponse,
              Twirp::Error,
            )
          )
        end
        def get_repository_installation(req, env)
          GitHub.tracer.in_span("sweagentd.twirp.get_repository_installation") do
            GitHub.dogstats.distribution_time("sweagentd.twirp.get_repository_installation") do
              ActiveRecord::Base.connected_to(role: :reading) do
                return Twirp::Error.invalid_argument("must be non-empty", argument: "repository_id") unless req.repository_id.present? && req.repository_id > 0

                repository = Repository.find_by(id: req.repository_id)
                return Twirp::Error.not_found("repository does not exist", argument: "repository_id") if repository.nil?

                repo_owner = repository.owner
                return Twirp::Error.not_found("repository owner does not exist") if repo_owner.nil?

                # Resolve the integration. When agent_id is unset (0), fall
                # back to the default global Copilot agent.
                agent_id = req.agent_id
                if agent_id == 0
                  agent = AgenticApp::CopilotAgent.instance
                  integration = agent.integration
                  return Twirp::Error.failed_precondition("agent integration is not configured") if integration.nil?
                else
                  integration = Integration.find_by(id: agent_id)
                  return Twirp::Error.invalid_argument("agent not found", argument: "agent_id") if integration.nil?
                  agent = AgenticApp.agent_for_bot_id(integration.bot_id)
                end

                is_global = agent&.global? || false

                installation_id = 0
                installation_permissions = {}
                unless is_global
                  installation = IntegrationInstallation.with_target(repo_owner).find_by(integration_id: integration.id)
                  if installation && installation.repository_ids(resource: "metadata", repository_ids: [repository.id]).include?(repository.id)
                    installation_id = installation.id
                    installation_permissions = installation.permissions.transform_values(&:to_s)
                  end
                end

                MonolithTwirp::Sweagentd::SweagentdAPI::V1::GetRepositoryInstallationResponse.new(
                  installation_id: installation_id,
                  owner_type: get_repository_owner_type(repo_owner),
                  client_id: integration.key || "",
                  is_global: is_global,
                  owner_login: repo_owner.login || "",
                  repo_name: repository.name || "",
                  owner_id: repo_owner.id,
                  permissions: installation_permissions,
                )
              end
            end
          end
        end

        # Public: Implementation of the integration_needs_authorization_from_user Twirp RPC.
        # Sweagentd calls this at job-execution time (gated by the
        # `copilot_swe_agent_check_agentic_app_auth` server flag) to refuse jobs for
        # agentic apps the requesting user hasn't authorized. Wraps the canonical
        # `AgenticApp::NeedsAuthorizationLookup` so we share logic with the GraphQL/REST
        # consent surfaces.
        sig do
          params(
            req: MonolithTwirp::Sweagentd::SweagentdAPI::V1::IntegrationNeedsAuthorizationFromUserRequest,
            env: T::Hash[T.untyped, T.untyped],
          ).returns(
            T.any(
              MonolithTwirp::Sweagentd::SweagentdAPI::V1::IntegrationNeedsAuthorizationFromUserResponse,
              Twirp::Error,
            )
          )
        end
        def integration_needs_authorization_from_user(req, env)
          GitHub.tracer.in_span("sweagentd.twirp.integration_needs_authorization_from_user", kind: :internal) do
            GitHub.dogstats.distribution_time("sweagentd.twirp.integration_needs_authorization_from_user") do
              ActiveRecord::Base.connected_to(role: :reading) do
                return Twirp::Error.invalid_argument("missing user_id", argument: "user_id") if req.user_id <= 0
                return Twirp::Error.invalid_argument("missing agent_id", argument: "agent_id") if req.agent_id <= 0

                user = User.find_by(id: req.user_id)
                return Twirp::Error.not_found("user does not exist", argument: "user_id") if user.nil?

                agent = agent_for_bot_id_or_default(req.agent_id)
                return Twirp::Error.not_found("agent not found", argument: "agent_id") if agent.nil?

                integration = agent.integration
                if integration.nil?
                  return MonolithTwirp::Sweagentd::SweagentdAPI::V1::IntegrationNeedsAuthorizationFromUserResponse.new(
                    needs_authorization: false,
                  )
                end

                needs_auth = AgenticApp::NeedsAuthorizationLookup.for_integration_ids(
                  user: user,
                  integration_ids: [integration.id],
                ).include?(integration.id)

                authorization_url = needs_auth ? authorization_url_for_integration(integration) : ""

                MonolithTwirp::Sweagentd::SweagentdAPI::V1::IntegrationNeedsAuthorizationFromUserResponse.new(
                  needs_authorization: needs_auth,
                  authorization_url: authorization_url,
                )
              end
            end
          end
        end

        private

        # Builds the OAuth start URL the viewer is sent to when authorizing an
        # agent's integration. Today this is the same per-user authorization
        # path used elsewhere in the consent flow.
        sig { params(integration: Integration).returns(String) }
        def authorization_url_for_integration(integration)
          query = { client_id: integration.key.to_s }.to_query
          "#{GitHub.url}/login/oauth/authorize?#{query}"
        end

        # Private: Maps a repository owner to the RepositoryOwnerType enum.
        sig { params(owner: User).returns(Symbol) }
        def get_repository_owner_type(owner)
          if owner.organization?
            :REPOSITORY_OWNER_TYPE_ORGANIZATION
          else
            :REPOSITORY_OWNER_TYPE_USER
          end
        end

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

        sig { params(repository: Repository).returns(T::Boolean) }
        def sandbox_policy_enabled_for_repository?(repository)
          owner = repository.owner
          # User-owned repositories don't have a Sandbox policy, so we assume it to be enabled
          return true unless owner.is_a?(Organization)

          business = owner.business
          enterprise_enabled = business.nil? || business.github_sandbox_enabled?
          organization_enabled = owner.github_sandbox_enabled?

          enterprise_enabled && organization_enabled
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

        # Best-effort grouping of a newly created pull request into a PR stack.
        # If the new PR's base branch matches an existing open PR's head branch,
        # they are grouped into a stack (or appended to one). Failures are reported
        # but do not affect the PR creation response.
        sig { params(repository: Repository, pull_request: PullRequest, attribution_user: User).void }
        def maybe_group_into_stack(repository, pull_request, attribution_user)
          return unless FeatureFlag.vexi.enabled?(:copilot_cloud_agent_pr_stacks, repository, default: false)
          return unless PullRequests::Stacks.enabled?(repository)

          base_ref = pull_request.base_ref
          return if base_ref == repository.default_branch

          parent_pulls = PullRequest.find_open_based_on_head_ref(repository.id, base_ref)
          return unless parent_pulls.size == 1

          parent_pull = parent_pulls.first
          return unless parent_pull.can_stack_on_top?

          result = PullRequests::Stacks.create_or_append(
            bottom: parent_pull,
            top: pull_request,
            actor: attribution_user,
          )

          case result
          when PullRequests::Stacks::Error
            GitHub.logger.info(
              "Stack grouping returned an error",
              "code.namespace": self.class.name,
              "gh.repo.id": repository.id,
              "gh.pull_request.id": pull_request.id,
              "gh.pull_request_stacks.error": result.message,
            )
          when PullRequests::Stacks::CreateOrAppend::Service::Success
            # Success: no-op
          else
            T.absurd(result)
          end
        rescue StandardError => e
          Failbot.report(e, app: "sweagentd", context: "maybe_group_into_stack")
        end
      end
    end
  end
end
