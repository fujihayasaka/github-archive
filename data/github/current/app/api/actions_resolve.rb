# typed: true
# frozen_string_literal: true

class Api::ActionsResolve < Api::App

  # Used to resolve:
  # All actions locally on GHES
  # Public actions fallback from GHES -> Dotcom (GitHub Connect)
  # Public actions fallback from Proxima -> Dotcom
  get "/repositories/:repository_id/actions/resolve/:ref", operation_id: :internal do
    @route_owner = "@github/c2c-actions-experience"

    # For now we're relying on a repository matching the nwo always being present even for package actions.
    # See https://github.com/github/package-registry-team/issues/7735
    repo = find_repo!

    # Bypass the logged-in check if a valid Proxima Service Identity token is present.
    # Proxima Service Identities are trusted GH first party services that are issued tokens
    # bound to a stamp and allows for interstamp dependencies on dotcom. These tokens are technically
    # unauthenticated/anonymous, but are allowed to access public resources.
    # Although this is an internal endpoint, it can only be used to access public repositories.
    skip_auth_when_psi_present = repo.feature_flag_enabled?(:proxima_service_identities_app_platform_access, default: false)

    psi_present = Api::RequestCredentials.from_env(env).proxima_service_token_present?

    GitHub.logger.info("check different methods of proxima service identity token presence",
      "gh.proxima_service_identity.token_present" => !!proxima_service_identity,
      "gh.proxima_service_identity.header_present" => psi_present) if skip_auth_when_psi_present

    if proxima_service_identity
      GitHub.logger.info("psi present",
        "gh.proxima_service_identity.service_name" => proxima_service_identity.service_name,
        "gh.proxima_service_identity.tenant_shortcode" => proxima_service_identity.tenant_shortcode)
    end
    unless proxima_service_identity && skip_auth_when_psi_present
      GitHub.logger.info("authenticating during actions resolution") if skip_auth_when_psi_present
      require_authentication!
    end

    control_access :resolve_actions,
      resource: repo,
      forbid: repo.public?,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    ref = CGI.unescape(params[:ref])

    log_fields = {
      catalog_service: "github/actions-sudo",
      "gh.request_id": GitHub.context[:request_id]
    }

    if !GitHub.actions_enabled?
      GitHub.dogstats.increment(
        "api.actions.resolve_action",
        tags: ["connect:#{connect_request?}", "error:actions_disabled"]
      )

      deliver_error!(404, message: "Unable to resolve action `#{repo.name_with_display_owner}@#{ref}`, GitHub Actions is not enabled")
    end

    workflow_repo = if params[:workflowRepoId].to_i > 0
      Repositories::Public.find_active(params[:workflowRepoId].to_i)
    else
      nil
    end

    proxima_fallback = if proxima_service_identity && skip_auth_when_psi_present
      true
    else
      Apps::Privileged.capable?(:resolve_public_dotcom_actions_via_proxima_fallback, app: current_integration)
    end

    if GitHub.enterprise?
      # Error out if the request does not come from the local Actions App.
      if !Apps::Privileged.capable?(:resolve_actions, app: current_integration)
        GitHub.dogstats.increment(
          "api.actions.resolve_action",
          tags: ["connect:#{connect_request?}", "error:app_insufficient_permissions"]
        )

        deliver_error!(404, message: "Unable to resolve action `#{repo.name_with_display_owner}@#{ref}`, invalid GitHub App authentication")
      end

      GitHub.logger.with_named_tags({ "gh.actions.resolver": "rest_v1" }.merge(log_fields)) do
        resolve_using_v1!(workflow_repo:, repo:, ref:, proxima_fallback:)
      end
    end

    ghes_fallback = Apps::Privileged.capable?(:resolve_public_dotcom_actions_via_github_connect, app: current_integration)

    # Error out if request does not come from GitHub Connect or Proxima Fallback.
    if !(ghes_fallback || proxima_fallback)
      GitHub.dogstats.increment(
        "api.actions.resolve_action",
        tags: ["connect:#{connect_request?}", "error:app_insufficient_permissions"]
      )

      deliver_error!(404, message: "Unable to resolve action `#{repo.name_with_display_owner}@#{ref}`, invalid GitHub App authentication")
    end

    if ghes_fallback && (repo.feature_flag_enabled_or_raise?(:serve_immutable_actions_over_connect_ghes) || repo.owner.feature_flag_enabled_or_raise?(:serve_immutable_actions_over_connect_ghes)) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
      GitHub.logger.with_named_tags({ "gh.actions.resolver": "rest_v2" }.merge(log_fields)) do
        resolve_using_v2!(workflow_repo:, repo:, ref:, proxima_fallback:)
      end
    elsif proxima_fallback && (repo.feature_flag_enabled_or_raise?(:serve_immutable_actions_over_connect_proxima) || repo.owner.feature_flag_enabled_or_raise?(:serve_immutable_actions_over_connect_proxima)) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
      GitHub.logger.with_named_tags({ "gh.actions.resolver": "rest_v2" }.merge(log_fields)) do
        resolve_using_v2!(workflow_repo:, repo:, ref:, proxima_fallback:)
      end
    else
      GitHub.logger.with_named_tags({ "gh.actions.resolver": "rest_v1" }.merge(log_fields)) do
        resolve_using_v1!(workflow_repo:, repo:, ref:, proxima_fallback:)
      end
    end
  end

  # This method is defined here to allow the ConditionalAccess
  # enforcer to skip access checks (specifically IP allow list) on
  # public repositories.
  def action
    :read
  end

  private

  # Can only serve public actions in GitHub Connect and Proxima Fallback.
  # Can't serve actions from the GHES instance itself yet.
  def resolve_using_v2!(workflow_repo:, repo:, ref:, proxima_fallback:)
    resolver = Actions::Resolver::V2::RestResolver.new(
      action_repo: repo,
      workflow_repo: workflow_repo,
      workflow_run_id: params[:workflowRunId].to_i,
      job_id: params[:jobId],
      connect_request: !!connect_request?,
      proxima_fallback_request: proxima_fallback,
      current_integration_installation: current_integration_installation,
      current_enterprise_installation: current_enterprise_installation)

    begin
      res = resolver.resolve(original_action_name: params["_action"], ref: ref)

      if res.success?
        res = T.cast(res, Actions::Resolver::Success)
        halt deliver_raw(res.body, status: res.status)
      else
        res = T.cast(res, Actions::Resolver::Error)
        deliver_error!(res.status, message: res.msg)
      end
    rescue PackageRegistry::Twirp::Error, ContainerRegistry::Twirp::Error => e
      Failbot.report(e)
      GitHub.logger.error("failed to resolve actions due to twirp error", e)

      deliver_error!(500, message: "Failed to resolve actions")
    end
  end

  # Can serve all actions in GHES and public actions in GitHub Connect and Proxima Fallback.
  def resolve_using_v1!(workflow_repo:, repo:, ref:, proxima_fallback:)
    resolver = Actions::Resolver::V1::RestResolver.new(
      action_repo: repo,
      workflow_repo: workflow_repo,
      workflow_run_id: params[:workflowRunId].to_i,
      job_id: params[:jobId],
      connect_request: !!connect_request?,
      proxima_fallback_request: proxima_fallback,
      current_integration_installation: current_integration_installation,
      current_enterprise_installation: current_enterprise_installation)

    res = resolver.resolve(original_action_name: params["_action"], ref: ref)
    if res.success?
      res = T.cast(res, Actions::Resolver::Success)
      halt deliver_raw(res.body, status: res.status)
    else
      res = T.cast(res, Actions::Resolver::Error)
      deliver_error!(res.status, message: res.msg)
    end
  end
end
