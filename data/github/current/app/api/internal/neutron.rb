# typed: true
# frozen_string_literal: true

class Api::Internal::Neutron < Api::Internal
  include Marketplace::Models::PlaygroundDependency
  include BaseHelpers::Helpers

  MICROSOFT_BUSINESS_SLUG = "microsoft"
  API_INSTRUMENTATION_PREFIX = "github_models.api."

  # Internal: Given an access token, this endpoint
  # checks if the token is valid and that the user is
  # allowed to use Neutron. If so, returns the user's ID.
  get "/internal/neutron/access", operation_id: :internal do
    @route_owner = "@github/github-models-reviewers"

    control_access :read_user,
      resource: current_user,
      challenge: true,
      allow_integrations: false,
      allow_user_via_granular_actor: true

    create_or_update_usage_details

    verify_integration_access!

    verify_playground_access!

    current_user = T.must_because(self.current_user) { ":read_user access check ensures not anonymous" }
    deliver_raw(
      {
        user_id: current_user.id,
        analytics_tracking_id: current_user.analytics_tracking_id,
        usage_tier: usage_tier,
        flights: flights,
        is_staff: is_staff?
      }
    )
  end

  sig { returns T::Boolean }
  def is_staff?
    current_user = self.current_user
    return false unless current_user
    return true if current_user.employee?
    return true if current_user.businesses.pluck(:slug).include?(MICROSOFT_BUSINESS_SLUG)
    return true if current_user.feature_enabled?(:project_neutron_staff_account)

    false
  end

  sig { returns T::Array[String] }
  def flights
    ret = []

    ret << "o1-models" if can_use_o1_models?(current_user)
    ret << "rag" if current_user&.feature_enabled?(:project_neutron_rag)

    ret
  end

  sig { returns Integer }
  def usage_tier
    return 0 if current_user&.feature_enabled?(:project_neutron_higher_rate_limits)

    current_plan = copilot_user&.copilot_plan
    if current_plan == "enterprise"
      1
    elsif current_plan == "business"
      2
    else
      3 # Free or Copilot Individual users get the same limits
    end
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
  def create_or_update_usage_details
    report_on_failure = -> { GitHub.dogstats.increment(API_INSTRUMENTATION_PREFIX +
      "auth_count_record_failure")
    }

    retry_on_find_or_create_error(on_max_retry: report_on_failure) do
      current_user = T.must_because(self.current_user) { "only called after verifying not anonymous" }
      model = AzureModels::UsageDetails.find_by(user_id: current_user.id)

      ActiveRecord::Base.connected_to(role: :writing) do
        if model.present?
          model.update(auths_count: model.auths_count + 1)
        else
          AzureModels::UsageDetails.create(user_id: current_user.id, auths_count: 1)
        end
      end
    end
  end

  sig { void }
  def verify_integration_access!
    return if current_user&.feature_enabled?(:project_neutron_allow_all_integrations)
    return unless current_integration

    return if current_integration.owner == current_user

    playground_integration_id = ::Apps::Privileged::Neutron.integration_id_finder.call
    return if current_integration.id == playground_integration_id

    allowed_owner_orgs = Organization.where(login: %w(copilot-extensions github githubnext Visual-Studio-Code))
    return if allowed_owner_orgs.include?(current_integration.owner)

    deliver_error! 401, message: "Integration auth is not supported for this endpoint"
  end

  sig { void }
  def verify_playground_access!
    feature_access_result = check_playground_access

    # Log the results of the feature access check
    event = {
      user: current_user,
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

    # Spammy, suspended, blocked, or trade restricted
    response_reason = "not_eligible"

    deliver_error! 404, message: { reason: response_reason }
  end

  private

  sig { returns T.nilable(Copilot::User) }
  def copilot_user
    current_user = self.current_user
    return unless current_user
    @copilot_user ||= Copilot::User.new(current_user)
  end
end
