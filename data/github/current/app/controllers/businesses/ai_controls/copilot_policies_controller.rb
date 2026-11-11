# typed: strict
# frozen_string_literal: true

# JSON endpoint for updating a single enterprise-mutable Copilot policy
# This can be used by the react frontend to update Copilot policies.
#
# This differs from `DefaultModelsController`, which is the controller that allows
# customers to set rules-based policies specifically for Copilot models.
class Businesses::AiControls::CopilotPoliciesController < Businesses::BusinessController
  include ApplicationController::JsonDependency
  include ApplicationController::VerifiedFetchDependency
  include Businesses::AiControls::Concerns::CopilotAuth

  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = T.let([
    "Businesses::AiControls::CopilotPoliciesController#update",
  ].freeze, T::Array[String])

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Copilot,
    ApplicationRecord::Billing

  before_action :login_required
  before_action :dotcom_required
  before_action :ai_controls_write_access_required
  before_action :business_not_downgraded_to_free_plan_required
  before_action :ensure_copilot_enabled

  allow_verified_fetch

  sig { void }
  def update
    begin
      body_json = JSON.parse(request.body.read)
    rescue JSON::ParserError
      render json: { error: "Malformed JSON" }, status: :bad_request
      return
    end

    unless body_json.is_a?(Hash)
      render json: { error: "Invalid parameters" }, status: :unprocessable_entity
      return
    end

    value = body_json["value"]
    unless value.is_a?(String)
      render json: { error: "Missing or invalid value" }, status: :unprocessable_entity
      return
    end

    policy_class = Copilot::Policies::BUSINESS_MUTABLE[params[:policy_name]]
    if policy_class.nil?
      render json: { error: "Unknown policy" }, status: :not_found
      return
    end

    unless policy_class.editable_by_business?(copilot_business)
      render json: { error: "Policy not editable" }, status: :forbidden
      return
    end

    unless valid_policy_value?(policy_class, value)
      render json: { error: "Invalid value" }, status: :unprocessable_entity
      return
    end

    policy_class.update_business(copilot_business, value)

    render json: {
      policyName: policy_class.config_name,
      value: policy_class.configuration_value(copilot_business),
    }
  end

  private

  # Mirrors the conditions under which Copilot::Policies::Concerns::Business::Mutable#update_business
  # silently no-ops, so we can reject those values with a 422 instead of returning a misleading 200.
  sig { params(policy_class: Copilot::PolicyInterface, value: String).returns(T::Boolean) }
  def valid_policy_value?(policy_class, value)
    config_values = policy_class.config_values

    # must be a value defined in the policy's configuration enum
    return false unless Copilot::Configuration.defined_enums[policy_class.config_name]&.key?(value)

    # the unconfigured value cannot be set via this paved path
    return false if value == config_values[:unconfigured]

    # standalone businesses have no orgs, so they cannot set no_policy
    return false if value == config_values[:no_policy] && copilot_business.is_standalone_business?

    true
  end
end
