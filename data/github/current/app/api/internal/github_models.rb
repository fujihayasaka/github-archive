# typed: true
# frozen_string_literal: true

class Api::Internal::GitHubModels < Api::Internal
  include ::GitHubModels::PlaygroundDependency
  include BaseHelpers::Helpers
  include GitHub::Memoizer

  API_INSTRUMENTATION_PREFIX = "github_models.api."
  ALLOWED_USER_TO_SERVER_TOKEN_ORGS = %w(copilot-extensions github githubnext Visual-Studio-Code)
  CATALOG_SERVICE = "github/github_models"

  # Internal: Given an access token, this endpoint
  # checks if the token is valid and that the user is
  # allowed to use GitHub Models (aka Neutron). If so, returns the user's ID.
  get "/internal/neutron/access", operation_id: :internal do
    @route_owner = "@github/github-models-reviewers"

    # Still use the `current_user` for the control access check so we can
    # rely on its protections for integrations.
    if current_user&.feature_enabled?(:github_models_user_model_permission_enforced)
      has_access = Api::AccessControl.access_allowed?(
        user: current_user, # rubocop:disable GitHub/DisallowEgressUserKey
        verb: :read_user_models,
        allow_integrations: true,
        allow_user_via_granular_actor: true,
      )
      unless has_access
        GitHub.logger.warn("Missing 'models' permission", {
          "code.namespace": "Api::Internal::GitHubModels",
          "code.function": "internal neutron access",
          "gh.user.id": current_user&.id,
          "gh.actor.name": actor_name,
          "gh.catalog_service": CATALOG_SERVICE,
        })
        deliver_error! 401, message: "The `models` permission is required to access this endpoint"
      end
    else
      control_access :read_user, resource: current_user,
        challenge: true,
        allow_integrations: true,
        allow_user_via_granular_actor: true
    end

    user = T.must_because(self.acting_owner) { "only called after verifying not anonymous" }
    ActiveRecord::Base.connected_to(role: :writing) do
      ::GitHubModels.domain.usage.create_or_update(user_id: user.id)
    end

    verify_integration_access!

    verify_playground_access!

    acting_owner = T.must_because(self.acting_owner) { ":read_user access check ensures not anonymous" }
    deliver_raw(
      {
        user_id: acting_owner.id,
        analytics_tracking_id: acting_owner.analytics_tracking_id,
        usage_tier: usage_tier,
        flights: flights,
        is_staff: is_staff?
      }
    )
  end

  # In this case, we're interested in whether the acting user is a staff
  # account so we can handle the Actions server-to-server example where the
  # acting user is the owner of the repo where the action is running.
  sig { returns T::Boolean }
  def is_staff?
    return false unless models_user == self.models_user
    models_user.is_staff?
  end

  # We're interested in the feature flags on the acting user so we can handle
  # the Actions server-to-server use case.
  sig { returns T::Array[String] }
  def flights
    return [] unless models_user == self.models_user
    models_user.access_flights
  end

  sig { returns Integer }
  def usage_tier
    return ::GitHubModels::User::USAGE_TIERS[:FREE] unless models_user == self.models_user
    models_user.usage_tier
  end

  sig { returns T::Boolean }
  def externally_accessible?
    true
  end

  sig { returns T::Boolean }
  def require_request_hmac?
    true
  end

  def self.request_hmac_keys
    GitHub.api_internal_neutron_hmac_keys
  end

  sig { void }
  def verify_integration_access!
    return if current_user&.feature_enabled?(:project_neutron_allow_all_integrations)

    unless current_integration
      GitHub.dogstats.increment("#{API_INSTRUMENTATION_PREFIX}user")
      return
    end

    if current_user&.bot?
      # if the acting user is different from a current user, we're dealing with
      # a server-to-server token, and the only scenario we want to handle
      # in that case for now is Actions usage.
      if ::Apps::Privileged.capable?(:bypass_github_models_user_models_permission, app: current_integration)
        GitHub.dogstats.increment("#{API_INSTRUMENTATION_PREFIX}actions")

        # check if we have the `models` FGP on the current token
        if current_integration_installation.permissions["models"] == :read
          return
        end

        GitHub.logger.warn("'models' permission is required", {
          "code.namespace": "Api::Internal::GitHubModels",
          "code.function": "verify_integration_access!",
          "gh.user.id": current_user&.id,
          "gh.actor.name": actor_name,
          "gh.catalog_service": CATALOG_SERVICE,
        })
        deliver_error! 401, message: "The `models` permission is required to access this endpoint"
      end
    else
      return if current_integration.owner == current_user

      return if current_integration == ::Apps::Privileged.integration(:neutron)

      allowed_owner_orgs = Organization.where(login: ALLOWED_USER_TO_SERVER_TOKEN_ORGS)
      return if allowed_owner_orgs.include?(current_integration.owner)
    end

    GitHub.logger.warn("Unsupported integration auth", {
      "code.namespace": "Api::Internal::GitHubModels",
      "code.function": "verify_integration_access!",
      "gh.user.id": current_user&.id,
      "gh.actor.name": actor_name,
      "gh.catalog_service": CATALOG_SERVICE,
    })
    deliver_error! 401, message: "Integration auth is not supported for this endpoint"
  end

  # We want to check the access for the acting user so org-owned
  # server-to-server tokens can also be blocked.
  sig { void }
  def verify_playground_access!
    feature_access_result = ::GitHubModels::PlaygroundAccessResult.for(current_user)

    # Log the results of the feature access check
    event = {
      user: acting_owner,
      success: feature_access_result.accessible?,
      reason: feature_access_result.reason
    }
    instrumentation_key = API_INSTRUMENTATION_PREFIX + "authentication_result"
    GlobalInstrumenter.instrument(instrumentation_key, event)
    GitHub.dogstats.increment(
      instrumentation_key,
      tags: [
        "success:#{feature_access_result.accessible?}",
        "reason:#{feature_access_result.reason}"
      ]
    )

    return if feature_access_result.accessible?

    # Since EMU disabled users can do something about it (contact their admin), let's feed the reason back
    # so we can display them a different message
    response_reason = if feature_access_result.reason == :emu_disabled
      "admin_disabled"
    else
      "not_eligible"
    end

    deliver_error! 404, message: { reason: response_reason }
  end

  private

  sig { returns T.nilable(Copilot::User) }
  def copilot_user
    current_user = self.current_user
    return unless current_user
    @copilot_user ||= Copilot::User.new(current_user)
  end

  sig { returns(::GitHubModels::User) }
  memoize def models_user
    acting_owner = self.acting_owner
    ::GitHubModels::User.new(user: acting_owner)
  end

  sig { returns T.nilable(User) }
  def acting_owner
    current_user = self.current_user
    return unless current_user

    @acting_owner ||= if current_user.bot?
      T.cast(current_user, Bot).installation.target
    else
      current_user
    end
  end
end
