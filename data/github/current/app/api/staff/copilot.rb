# typed: true
# frozen_string_literal: true

class Api::Staff::Copilot < Api::Staff::App
  before do
    deliver_error! 404 if GitHub.enterprise?
    deliver_error! 404 unless current_user.feature_flag_enabled?(:copilot_staff_api, default: false)
  end

  post "/staff/copilot/enterprise_activation/enterprises/:enterprise_id", operation_id: :internal, resolve_tenant_context: :resolve_tenant_from_enterprise, read_from_replicas: true do # rubocop:todo GitHub/ControlAccess
    @route_owner = "@github/copilot"

    business = find_enterprise!
    copilot_business = Copilot::Business.new(business)
    if blocked_because_dfd_trial?(business)
      deliver_raw({ message: "Enterprise is blocked from copilot enablement because it is a DFD trial" }, status: 404)
    elsif !copilot_business.copilot_enablement_blocked?
      deliver_raw({ message: "Enterprise already is not blocked from copilot enablement" }, status: 200)
    else
      # rubocop:disable GitHub/FeatureManagement/NoActorFeatureFlagManipulation
      business.enable_feature_flag(:allow_enterprise_copilot_activation)
      # rubocop:enable GitHub/FeatureManagement/NoActorFeatureFlagManipulation

      GitHub.logger.info(
        "Copilot enablement unblocked via staff API",
        "gh.biz.slug" => business.slug,
        "gh.actor.login" => current_user.display_login,
      )

      deliver_raw({ message: "allow_enterprise_copilot_activation enabled for #{business.slug}" }, status: 201)
    end
  end

  get "/staff/copilot/enterprise_activation/enterprises/:enterprise_id", operation_id: :internal, resolve_tenant_context: :resolve_tenant_from_enterprise, read_from_replicas: true do # rubocop:todo GitHub/ControlAccess
    @route_owner = "@github/copilot"
    business = find_enterprise!

    copilot_business = Copilot::Business.new(business)
    deliver_raw({
      enterprise_slug: business.slug,
      allow_enterprise_copilot_activation: business.feature_flag_enabled?(:allow_enterprise_copilot_activation, default: false),
      copilot_enablement_blocked: blocked_because_dfd_trial?(business) || copilot_business.copilot_enablement_blocked?,
    }, status: 200)
  end

  delete "/staff/copilot/enterprise_activation/enterprises/:enterprise_id", operation_id: :internal, resolve_tenant_context: :resolve_tenant_from_enterprise, read_from_replicas: true do # rubocop:todo GitHub/ControlAccess
    @route_owner = "@github/copilot"
    business = find_enterprise!
    copilot_business = Copilot::Business.new(business)

    if !copilot_business.copilot_enablement_blocked?
      # rubocop:disable GitHub/FeatureManagement/NoActorFeatureFlagManipulation
      business.disable_feature_flag(:allow_enterprise_copilot_activation)
      # rubocop:enable GitHub/FeatureManagement/NoActorFeatureFlagManipulation

      GitHub.logger.info(
        "Copilot enablement re-blocked via staff API",
        "gh.biz.slug" => business.slug,
        "gh.actor.login" => current_user.display_login,
      )

      deliver_raw({ message: "allow_enterprise_copilot_activation disabled for #{business.slug}" }, status: 200)
    else
      deliver_raw({ message: "Enterprise is not blocked from copilot enablement" }, status: 404)
    end
  end

  def resolve_tenant_from_enterprise
    find_enterprise!
  end

  private

  def blocked_because_dfd_trial?(business)
    business.trial? && business.copilot_trial_activation_blocked?
  end
end
