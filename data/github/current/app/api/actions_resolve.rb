# typed: true
# frozen_string_literal: true

class Api::ActionsResolve < Api::App

  # Used to resolve:
  # All actions locally on GHES
  # Public actions fallback from GHES -> Dotcom (GitHub Connect)
  # Public actions fallback from Proxima -> Dotcom
  get "/repositories/:repository_id/actions/resolve/:ref", operation_id: :internal do
    @route_owner = "@github/c2c-actions-experience"
    require_authentication!

    # For now we're relying on a repository matching the nwo always being present even for package actions.
    # See https://github.com/github/package-registry-team/issues/7735
    repo = find_repo!
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
        resolve_using_v1!(workflow_repo: workflow_repo, repo: repo, ref: ref)
      end
    end

    # Error out if request does not come from GitHub Connect or Proxima Fallback.
    if !Apps::Privileged.capable?(:resolve_public_dotcom_actions_via_github_connect, app: current_integration) && !Apps::Privileged.capable?(:resolve_public_dotcom_actions_via_proxima_fallback, app: current_integration)
      GitHub.dogstats.increment(
        "api.actions.resolve_action",
        tags: ["connect:#{connect_request?}", "error:app_insufficient_permissions"]
      )

      deliver_error!(404, message: "Unable to resolve action `#{repo.name_with_display_owner}@#{ref}`, invalid GitHub App authentication")
    end

    if repo.feature_enabled?(:serve_immutable_actions_over_connect) || repo.owner.feature_enabled?(:serve_immutable_actions_over_connect)
      GitHub.logger.with_named_tags({ "gh.actions.resolver": "rest_v2" }.merge(log_fields)) do
        resolve_using_v2!(workflow_repo: workflow_repo, repo: repo, ref: ref)
      end
    else
      GitHub.logger.with_named_tags({ "gh.actions.resolver": "rest_v1" }.merge(log_fields)) do
        resolve_using_v1!(workflow_repo: workflow_repo, repo: repo, ref: ref)
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
  def resolve_using_v2!(workflow_repo:, repo:, ref:)
    resolver = Actions::Resolver::V2::RestResolver.new(
      action_repo: repo,
      workflow_repo: workflow_repo,
      workflow_run_id: params[:workflowRunId].to_i,
      job_id: params[:jobId],
      connect_request: !!connect_request?,
      proxima_fallback_request: Apps::Privileged.capable?(:resolve_public_dotcom_actions_via_proxima_fallback, app: current_integration),
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
  def resolve_using_v1!(workflow_repo:, repo:, ref:)
    resolver = Actions::Resolver::V1::RestResolver.new(
      action_repo: repo,
      workflow_repo: workflow_repo,
      workflow_run_id: params[:workflowRunId].to_i,
      job_id: params[:jobId],
      connect_request: !!connect_request?,
      proxima_fallback_request: Apps::Privileged.capable?(:resolve_public_dotcom_actions_via_proxima_fallback, app: current_integration),
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
