# typed: false
# frozen_string_literal: true

class Api::Internal::Neutron < Api::Internal
  include Marketplace::Models::PlaygroundDependency

  # Internal: Given an access token, this endpoint
  # checks if the token is valid and that the user is
  # allowed to use Neutron. If so, returns the user's ID.
  get "/internal/neutron/access", operation_id: :internal do
    @route_owner = "@github/neutron-reviewers"

    control_access :read_user,
      resource: current_user,
      challenge: true,
      allow_integrations: false,
      allow_user_via_granular_actor: true

    verify_playground_access!

    deliver_raw(
      {
        user_id: current_user.id,
        analytics_tracking_id: current_user.analytics_tracking_id,
        usage_tier: usage_tier
      }
    )
  end

  def usage_tier
    return 0 if current_user.feature_enabled?(:project_neutron_higher_rate_limits)

    current_plan = Copilot::User.new(current_user).copilot_plan
    if current_plan == "enterprise"
      1
    elsif current_plan == "business"
      2
    else
      3 # Free or Copilot Individual users get the same limits
    end
  end

  def externally_accessible?
    true
  end

  def require_request_hmac?
    true
  end

  def self.request_hmac_keys
    GitHub.api_internal_neutron_hmac_keys
  end

  def verify_playground_access!
    feature_access_result = check_playground_access

    # Log the results of the feature access check
    event = {
      user: current_user,
      success: feature_access_result.accessible?,
      reason: feature_access_result.reason
    }
    GlobalInstrumenter.instrument("github_models.api.authentication_result", event)
    GitHub.dogstats.increment(
      "github_models.api.authentication_result",
      tags: [
        "success:#{feature_access_result.accessible?}",
        "reason:#{feature_access_result.reason}"
      ]
    )

    return if feature_access_result.accessible?

    response_reason = if feature_access_result.reason == :feature_flag_disabled
      if EarlyAccessMembership.on_waitlist?(::Marketplace::ModelsBeta.new.feature_slug, current_user)
        "on_waitlist"
      else
        "not_on_waitlist"
      end
    else
      # Spammy, suspended, or trade restricted
      "not_eligible"
    end

    deliver_error! 404, message: { reason: response_reason }
  end
end
