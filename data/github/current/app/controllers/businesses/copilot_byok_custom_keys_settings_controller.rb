# typed: true
# frozen_string_literal: true

class Businesses::CopilotByokCustomKeysSettingsController < Businesses::BusinessController
  include ApplicationController::JsonDependency
  include ApplicationController::VerifiedFetchDependency

  before_action :dotcom_required
  before_action :business_owner_required
  before_action :business_not_downgraded_to_free_plan_required
  before_action :ensure_copilot_enabled
  before_action :parse_json_params, only: [:update, :destroy]
  before_action :require_json_request, only: :update

  # Allow making requests to this endpoint from React apps using the `verifiedFetch` function:
  allow_verified_fetch only: [:update, :destroy]

  def destroy
    custom_key.actor = current_user
    custom_key.destroy!
    head :ok
  end

  def update
    provider_data = update_params[:provider_data].to_h
    provider_data = nil if provider_data.empty?
    error = CopilotByok::UpdateCustomKey.call(
      custom_key: custom_key,
      actor: current_user,
      name: update_params[:name],
      deployment_url: update_params[:deployment_url],
      models: update_params[:models]&.map(&:to_h),
      api_key: update_params[:api_key],
      access_key: update_params[:access_key],
      provider_data: provider_data,
    )
    if error
      render json: { message: error.message }, status: :unprocessable_entity
    else
      head :ok
    end
  end

  private

  sig { returns ActionController::Parameters }
  memoize def update_params
    params.permit(
      :name, :deployment_url, :api_key, :access_key, :id, :format, :slug,

      # Allowed provider-specific data for the custom key:
      provider_data: %i(base_url region deployment_url),

      models: [:id, :name, :slug, :maxOutputTokens,
        # Allowed provider-specific data for custom models:
        provider_data: [:inference_type, :model_arn, :inference_policy_arn, inference_policy_regions: []]],
    )
  end

  sig { returns(Copilot::Business) }
  memoize def copilot_business
    Copilot::Business.new(this_business)
  end

  sig { returns(CopilotByok::CustomKey) }
  memoize def custom_key
    this_business.copilot_custom_keys.find(params.expect(:id))
  end

  def require_json_request
    unless request.format.json?
      render json: { message: "Only JSON format is supported" }, status: :not_acceptable
    end
  end

  sig { void }
  def ensure_copilot_enabled
    render_404 unless copilot_business.copilot_enabled?
  end
end
