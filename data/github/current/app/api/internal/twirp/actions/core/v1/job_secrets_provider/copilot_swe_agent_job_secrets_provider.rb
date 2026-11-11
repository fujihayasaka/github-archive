# typed: strict
# frozen_string_literal: true

module Api::Internal::Twirp::Actions
  module Core
    module V1
      module JobSecretsProvider
        class CopilotSweAgentJobSecretsProvider
          include GitHub::Memoizer

          COPILOT_SWE_AGENT_JOB_SECRETS_PROVIDER = "copilot_swe_agent/job_secrets_provider"
          COPILOT_DISABLED_IN_MULTI_TENANT_MESSAGE = T.let("not_used_in_multitenant", String)
          RELEASE_ASSET_NAME = T.let("copilot-developer-action.tar.gz", String)
          AUTOFIND_RELEASE_ASSET_NAME = T.let("autofind.tar.gz", String)
          CAPI_INTEGRATION_ID = T.let("copilot-developer", String)

          # Actor types passed via COPILOT_AGENT_ACTOR_TYPE from the job executor.
          ACTOR_TYPE_ORG = T.let("org", String)

          class CopilotSweAgentJobSecretsError < StandardError; end
          class GetSecretsError < CopilotSweAgentJobSecretsError; end
          class NotFoundError < CopilotSweAgentJobSecretsError; end

          sig do
            params(
              agentic_app: ::AgenticApp,
              repository: T.nilable(Repository),
              workflow_run: T.nilable(Actions::WorkflowRun),
              bare_job_name: T.nilable(String),
              environment_name: T.nilable(String),
              is_hosted_runner: T.nilable(T::Boolean),
              dynamic_workflow: T.nilable(MonolithTwirp::Actions::Core::V1::DynamicWorkflow),
              integration_id: String,
            ).void
          end
          def initialize(agentic_app, repository, workflow_run, bare_job_name, environment_name, is_hosted_runner, dynamic_workflow, integration_id)
            @agentic_app = agentic_app
            @repository = repository
            @workflow_run = workflow_run
            @bare_job_name = bare_job_name
            @environment_name = environment_name
            @is_hosted_runner = is_hosted_runner
            @dynamic_workflow = dynamic_workflow
            @integration_id = integration_id
          end

          sig { returns(T::Hash[Symbol, String]) }
          def get_secrets
            raise NotFoundError, "repository is missing" if @repository.nil?
            raise NotFoundError, "workflow_run is missing" if @workflow_run.nil?
            raise NotFoundError, "dynamic_workflow is missing" if @dynamic_workflow.nil?

            raise NotFoundError, "dynamic_workflow.inputs is missing" if @dynamic_workflow.inputs.nil?

            actor_type = @dynamic_workflow.inputs["COPILOT_AGENT_ACTOR_TYPE"]
            org_billed = actor_type == ACTOR_TYPE_ORG

            user_id = @dynamic_workflow.inputs["COPILOT_AGENT_ACTOR_ID"]
            user = org_billed ? nil : User.find_by(id: user_id)

            u2s_unless_cant = org_billed ||
              user&.feature_flag_enabled?(:copilot_swe_agent_u2s_unless_cant, default: false) ||
              @repository.feature_flag_enabled?(:copilot_swe_agent_u2s_unless_cant, default: false)

            raise NotFoundError, "COPILOT_AGENT_ACTOR_ID is missing from inputs" if user_id.nil? && !u2s_unless_cant
            raise NotFoundError, "user does not exist" if user.nil? && !u2s_unless_cant

            # Check enablement
            return {} unless @agentic_app.enabled_for_repository?(@repository, user)

            # Copilot SWE Agent does not support re-running the job via Actions CI. So return empty job/cred token to the
            # the Copilot SWE Agent job if the this is a re-run job via Actions CI.
            # This will fail the re-run Copilot SWE Agent job which is expected behavior.
            if @workflow_run.has_multiple_attempts && (user_id.nil? || user.nil? || !user.feature_flag_enabled_or_raise?(:copilot_swe_agent_job_secrets_provider_re_run)) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
              GitHub.logger.info(
                "Re-running Copilot SWE Agent jobs via Actions CI is not supported.",
                "code.namespace" => self.class.name,
                "code.function" => __method__,
                "gh.repository.id" => @repository.id,
                "gh.workflow_run.id" => @workflow_run.id,
              )
              return {}
            end

            integration = @agentic_app.integration
            raise NotFoundError, "integration does not exist" if integration.nil?

            action_download_url = get_action_download_url(user)
            autofind_download_url = get_autofind_download_url(user)

            if u2s_unless_cant
              # If ff enabled, use u2s if user provided and down-scope perms based on user / app
              git_token = mint_repo_scoped_installation_token(agentic_app: @agentic_app, permissions: GIT_TOKEN_PERMISSIONS, auto_down_scope: true)
              if user
                api_token = mint_repo_scoped_user_token(integration: integration, user: user, permissions: API_TOKEN_PERMISSIONS, auto_down_scope: true)
                gh_token = mint_repo_scoped_user_token(integration: integration, user: user, permissions: get_token_permissions, auto_down_scope: true)
              else
                api_token = mint_repo_scoped_installation_token(agentic_app: @agentic_app, permissions: API_TOKEN_PERMISSIONS, auto_down_scope: true)
                gh_token = mint_repo_scoped_installation_token(agentic_app: @agentic_app, permissions: get_token_permissions, auto_down_scope: true)
              end
            else
              # Use existing behaviors unless if ff disabled - would have errored above if no user
              api_token = mint_repo_scoped_user_token(integration: integration, user: T.must(user))
              git_token = mint_repo_scoped_installation_token(agentic_app: @agentic_app, permissions: GIT_TOKEN_PERMISSIONS)
              gh_token = mint_repo_scoped_installation_token(agentic_app: @agentic_app, permissions: get_token_permissions)
            end

            {
              "GITHUB_COPILOT_GIT_TOKEN": git_token,
              "GITHUB_COPILOT_API_TOKEN": api_token,
              "GITHUB_COPILOT_GITHUB_TOKEN": gh_token,
              "GITHUB_COPILOT_INTEGRATION_ID": @integration_id,
              "GITHUB_COPILOT_ACTION_DOWNLOAD_URL": action_download_url,
              "GITHUB_COPILOT_AUTOFIND_DOWNLOAD_URL": autofind_download_url,
            }
          rescue StandardError => e # rubocop:todo Lint/RescueException
            raise GetSecretsError, "Error in get_secrets: #{e.message}"
          end

          private

          # Note: this method will not work in multi-tenant mode!
          sig { returns(Repository) }
          memoize def action_repo
            Repository.nwo("github/copilot-developer-action")
          end

          sig { params(user: T.nilable(User)).returns(String) }
          def get_action_download_url(user)
            return COPILOT_DISABLED_IN_MULTI_TENANT_MESSAGE if GitHub.multi_tenant_enterprise?

            runtime_version_tag = get_runtime_version_tag(user)

            # Use tag format to determine download method while we change this. That way we only need to check
            # the feature flag state in sweagentd.
            #
            # App-specific tags (runtime-{app}-{sha}) use release assets
            # Old format tags (runtime-{sha}) or branch names use codeload
            if app_specific_runtime_tag?(runtime_version_tag)
              url = try_get_action_release_asset_url(runtime_version_tag)
              if url
                url
              else
                # Fallback to codeload if release not found (e.g., in staging)
                GitHub.logger.info(
                  "Falling back to codeload URL for app-specific tag",
                  "code.namespace" => self.class.name,
                  "code.function" => __method__,
                  "runtime_version_tag" => runtime_version_tag,
                  "reason" => "release_or_asset_not_found",
                )
                get_action_download_url_codeload(user, runtime_version_tag)
              end
            else
              get_action_download_url_codeload(user, runtime_version_tag)
            end
          end

          sig { params(user: T.nilable(User)).returns(String) }
          def get_autofind_download_url(user)
            return "" if GitHub.multi_tenant_enterprise?
            runtime_version_tag = get_runtime_version_tag(user)
            return "" unless app_specific_runtime_tag?(runtime_version_tag)

            # The autofind release uses the same SHA as the runtime but with a different prefix, so we can derive the tag from the runtime tag.
            # Runtime tag format: runtime-{app}-{sha}, where app can be any slug (e.g., "copilot", "foo-bar")
            autofind_version_tag = runtime_version_tag.sub(/\Aruntime-[a-zA-Z0-9]+(?:-[a-zA-Z0-9]+)*-/, "autofind-")
            release = T.cast(
              Releases::Public.load_by_tag(action_repo.id, autofind_version_tag),
              T.nilable(Release)
            )

            if release.nil?
              GitHub.logger.info(
                "Autofind release not found for tag",
                "code.namespace" => self.class.name,
                "code.function" => __method__,
                "runtime_version_tag" => runtime_version_tag,
                "autofind_version_tag" => autofind_version_tag,
                "gh.repository.id" => action_repo.id,
              )
              return ""
            end

            asset = release.uploaded_assets.find_by(name: AUTOFIND_RELEASE_ASSET_NAME)
            if asset.nil?
              GitHub.logger.info(
                "Autofind asset not found in release",
                "code.namespace" => self.class.name,
                "code.function" => __method__,
                "runtime_version_tag" => runtime_version_tag,
                "autofind_version_tag" => autofind_version_tag,
                "asset_name" => AUTOFIND_RELEASE_ASSET_NAME,
                "gh.repository.id" => action_repo.id,
              )
              return ""
            end

            # On GitHub.com, generates Azure SAS URL directly via MemoryAlphaWithDirectAbsDownloadPolicy
            # No actor needed - the URL contains embedded credentials
            asset.url
          end

          # Detects if a tag is in the app-specific format: runtime-{app}-{sha}
          # Example: runtime-copilot-738051eee1246fbfd88e3a6e46f35c82f38c7740
          sig { params(tag: String).returns(T::Boolean) }
          def app_specific_runtime_tag?(tag)
            # Pattern: runtime-{app_slug}-{40_char_sha}
            # The app slug can contain alphanumeric chars and internal hyphens (no leading/trailing hyphen)
            # The SHA is exactly 40 hex characters
            tag.match?(/\Aruntime-([a-zA-Z0-9]+(?:-[a-zA-Z0-9]+)*)-([a-f0-9]{40})\z/)
          end

          sig { params(user: T.nilable(User)).returns(String) }
          def get_runtime_version_tag(user)
            if !user || user.feature_flag_enabled?(:copilot_swe_agent_safe_runtime_deploy, default: false)
              runtime_version_tag = T.must(@dynamic_workflow).inputs["COPILOT_AGENT_RUNTIME_VERSION"]
              raise NotFoundError, "COPILOT_AGENT_RUNTIME_VERSION is missing from inputs" if runtime_version_tag.nil?
              runtime_version_tag
            else
              action_repo.default_branch
            end
          end

          # Attempts to get the release asset URL, returns nil if not found (with logging)
          sig { params(runtime_version_tag: String).returns(T.nilable(String)) }
          def try_get_action_release_asset_url(runtime_version_tag)
            release = T.cast(
              Releases::Public.load_by_tag(action_repo.id, runtime_version_tag),
              T.nilable(Release)
            )

            if release.nil?
              GitHub.logger.info(
                "Release not found for tag",
                "code.namespace" => self.class.name,
                "code.function" => __method__,
                "runtime_version_tag" => runtime_version_tag,
                "gh.repository.id" => action_repo.id,
              )
              return nil
            end

            asset = release.uploaded_assets.find_by(name: RELEASE_ASSET_NAME)
            if asset.nil?
              GitHub.logger.info(
                "Asset not found in release",
                "code.namespace" => self.class.name,
                "code.function" => __method__,
                "runtime_version_tag" => runtime_version_tag,
                "asset_name" => RELEASE_ASSET_NAME,
                "gh.repository.id" => action_repo.id,
              )
              return nil
            end

            # On GitHub.com, generates Azure SAS URL directly via MemoryAlphaWithDirectAbsDownloadPolicy
            # No actor needed - the URL contains embedded credentials
            asset.url
          end

          sig { params(user: T.nilable(User), runtime_version_tag: String).returns(String) }
          def get_action_download_url_codeload(user, runtime_version_tag)
            # We hardcode to Copilot here because we need a global installation to
            # download the runtime as non-global apps will not be installed on this repo.
            copilot_integration = ::AgenticApp::CopilotAgent.instance.integration

            result = ActiveRecord::Base.connected_to(role: :writing) do
              SiteScopedIntegrationInstallation::Creator.perform(
                copilot_integration,
                action_repo.owner,
                repositories: [action_repo],
                permissions: {
                  "metadata" => :read,
                  "contents" => :read,
                },
                entry_point: :twirp_api_copilot_swe_agent_job_secrets_provider
              )
            end

            ac = action_repo.archive_command(runtime_version_tag, "tar.gz")
            ac.codeload_url(result.installation.bot)
          end

          # Create a new scoped access for the user to the repository. This uses global installations to
          # ensure we're not creating a new installation. It also will automatically down-scope access
          # to the intersection of the app's permissions and the user. This avoids over-privileging and any
          # unexpected failures due to token generation where no good UX surface exists.
          sig { params(integration: Integration, user: User, permissions: T.nilable(T::Hash[String, Symbol]), auto_down_scope: T::Boolean).returns(String) }
          def mint_repo_scoped_user_token(integration:, user:, permissions: nil, auto_down_scope: false)
            repo_owner = T.must(@repository).owner
            raise NotFoundError, "repo_owner is missing" if repo_owner.nil?

            # Intersect requested permissions with what the user and the app are actually allowed to do
            effective_permissions = if auto_down_scope
              intersect_permissions_with_user_and_app_access(T.must(permissions), user, integration)
            elsif permissions
              permissions
            else
              API_TOKEN_PERMISSIONS
            end

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
                permissions: effective_permissions,
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

          # Down-scope each requested permission to the minimum of what the user has on the repository
          # and what the app (integration) has been granted. Permissions that neither the user nor the
          # app have access to are dropped entirely.
          sig { params(permissions: T::Hash[String, Symbol], user: User, integration: Integration).returns(T::Hash[String, Symbol]) }
          def intersect_permissions_with_user_and_app_access(permissions, user, integration)
            repo = T.must(@repository)
            app_permissions = integration.default_permissions
            ranking = Permission::ACTION_RANKING
            result = T.let({}, T::Hash[String, Symbol])

            permissions.each do |subject, requested_action|
              # Skip if the app doesn't have this permission at all
              app_action = app_permissions[subject]
              next if app_action.nil?

              resource = repo.resources.collection_for(subject)
              next if resource.nil?

              user_action = if resource.adminable_by?(user)
                :admin
              elsif resource.writable_by?(user)
                :write
              elsif resource.readable_by?(user)
                :read
              end

              next if user_action.nil?

              # Take the most restrictive of requested, user, and app permissions
              actions = [requested_action, user_action, app_action]
              effective_action = actions.min_by { |a| ranking[a] }
              result[subject] = effective_action
            end

            result
          end

          # Down-scope each requested permission to what the app (integration) has been granted.
          # Permissions the app doesn't have are dropped entirely.
          sig { params(permissions: T::Hash[String, Symbol], integration: Integration).returns(T::Hash[String, Symbol]) }
          def intersect_permissions_with_app_access(permissions, integration)
            app_permissions = integration.default_permissions
            ranking = Permission::ACTION_RANKING
            result = T.let({}, T::Hash[String, Symbol])

            permissions.each do |subject, requested_action|
              app_action = app_permissions[subject]
              next if app_action.nil?

              effective_action = ranking[requested_action] <= ranking[app_action] ? requested_action : app_action
              result[subject] = effective_action
            end

            result
          end

          GIT_TOKEN_PERMISSIONS = T.let({
            "contents" => :write,
            "metadata" => :read,
            "workflows" => :write,
          }, T::Hash[String, Symbol])

          # Default GitHub token permissions for use with the GitHub MCP server
          DEFAULT_GITHUB_TOKEN_PERMISSIONS = T.let({
              "metadata" => :read,
              "contents" => :read,
              "issues" => :read,
              "pull_requests" => :read,
              "actions" => :read,
          }, T::Hash[String, Symbol])

          # TODO: Once we roll out switching GH MCP over to the new GITHUB_COPILOT_GITHUB_TOKEN, we can
          # reduce the permissions here to only what is needed to call CAPI (e.g. just github-copilot).
          # Most of these scopes are due to this token's use by the MCP server.
          API_TOKEN_PERMISSIONS = T.let({
              "metadata" => :read,
              "contents" => :read,
              "issues" => :read,
              "pull_requests" => :read,
              "actions" => :read,
          }, T::Hash[String, Symbol])

          #
          # **WARNING**
          #
          # If you are here to look into implementing multi-repo support, be aware that the
          # permissions here are currently for a s2s/installation token, NOT a user token.
          # Given the CCA app has access to all repos, this means that you could technically
          # mint a token for a location that the user does not themselves have access to.
          # Right now we scope to the triggering repo, which means this is not currently an issue.
          #
          # A secondary validation will be required here to light up this scenario, or we will
          # need to use a user token. If we did that, CI / "triggered" scenarios where this is
          # not possible, we'd have to limit to single repo.
          #

          # Parse permissions from JSON input or use defaults
          sig { returns(T::Hash[String, Symbol]) }
          def get_token_permissions
            permissions_input = T.must(@dynamic_workflow).inputs["COPILOT_AGENT_PERMISSIONS"]
            if permissions_input.blank?
              DEFAULT_GITHUB_TOKEN_PERMISSIONS
            else
              # Allow the caller (sweagentd) to define the permissions of this token. Notably,
              # the token will still be repo-scoped but it could include destructive permissions like "admin".
              # That validation is up to sweagentd to implement, as we want admin capabilities to be possible
              # in very specific (non-user-provided) scenarios.
              parsed_permissions = JSON.parse(permissions_input)
              unless parsed_permissions.is_a?(Hash)
                raise GetSecretsError, "COPILOT_AGENT_PERMISSIONS must be a JSON object"
              end
              unless parsed_permissions.values.all? { |v| v.is_a?(String) }
                raise GetSecretsError, "All permission values must be strings"
              end
              parsed_permissions.transform_values(&:to_sym)
            end
          end

          # Mint a repo-scoped token for the installation on the repository.
          # This token will be used to interact with GitHub (ex: `git push`) as Copilot, not as Actions.
          # Permissions are down-scoped to the intersection of the requested permissions and what the
          # app (integration) has been granted.
          sig { params(agentic_app: AgenticApp, permissions: T::Hash[String, Symbol], auto_down_scope: T::Boolean).returns(String) }
          def mint_repo_scoped_installation_token(agentic_app:, permissions:, auto_down_scope: false)

            # Intersect requested permissions with what the user and the app are actually allowed to do
            effective_permissions = if auto_down_scope
              intersect_permissions_with_app_access(permissions, agentic_app.integration)
            elsif permissions
              permissions
            end

            if agentic_app.global?
              return mint_repo_scoped_installation_token_with_global_integration(integration: agentic_app.integration, permissions: effective_permissions)
            end

            # non-global app path
            installation = IntegrationInstallation.with_repository(@repository).find_by(integration: agentic_app.integration)
            raise NotFoundError, "installation not found for repository" if installation.nil?

            scoped_installation_result = ScopedIntegrationInstallation::Creator.perform_with_cache(
              installation,
              repositories: [T.must(@repository)],
              permissions: effective_permissions,
              entry_point: :twirp_api_copilot_swe_agent_job_secrets_provider
            )

            if scoped_installation_result.failed?
              raise GetSecretsError, "Failed to create scoped installation: #{scoped_installation_result.error}"
            end

            scoped_installation = scoped_installation_result.installation

            token_result = scoped_installation.generate_token(
              code_path: COPILOT_SWE_AGENT_JOB_SECRETS_PROVIDER,
              redis_with_mysql_fallback: ServerToServerTokens.domain.redis_with_mysql_fallback?([
                agentic_app.integration, installation.target
              ])
            )

            if !token_result.ok?
              raise GetSecretsError, "Failed to generate token for scoped installation: #{token_result.error}"
            end

            token_result.value.token_value
          end


          # Mint a repo-scoped installation token using the global installation of the integration.
          sig { params(integration: Integration, permissions: T::Hash[String, Symbol]).returns(String) }
          def mint_repo_scoped_installation_token_with_global_integration(integration:, permissions:)
            result = ActiveRecord::Base.connected_to(role: :writing) do
              SiteScopedIntegrationInstallation::Creator.perform(
                integration,
                T.must(@repository).owner,
                repositories: [@repository],
                permissions: permissions,
                entry_point: :twirp_api_copilot_swe_agent_job_secrets_provider
              )
            end

            response = result.installation.generate_token(
              code_path: COPILOT_SWE_AGENT_JOB_SECRETS_PROVIDER,
              redis_with_mysql_fallback: ServerToServerTokens.domain.redis_with_mysql_fallback?([
                integration, T.must(@repository).owner
              ])
            )

            case response
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
