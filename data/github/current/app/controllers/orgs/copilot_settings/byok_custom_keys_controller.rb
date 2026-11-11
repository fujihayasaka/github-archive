# typed: true
# frozen_string_literal: true

class Orgs::CopilotSettings::ByokCustomKeysController < Orgs::Controller
  include ApplicationController::JsonDependency
  include ApplicationController::VerifiedFetchDependency

  before_action :organization_admin_required
  before_action :copilot_required
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
      :name, :deployment_url, :api_key, :access_key, :organization_id, :id, :format,

      # Allowed provider-specific data for the custom key:
      provider_data: %i(base_url region deployment_url),

      models: [:id, :name, :slug, :maxOutputTokens,
        # Allowed provider-specific data for custom models:
        provider_data: [:inference_type, :model_arn, :inference_policy_arn, inference_policy_regions: []]],
    )
  end

  sig { returns(::Organization) }
  memoize def org
    T.cast(this_organization, ::Organization)
  end

  sig { returns(CopilotByok::CustomKey) }
  memoize def custom_key
    org.copilot_custom_keys.find(params.expect(:id))
  end

  def require_json_request
    render json: { message: "Only JSON format is supported" }, status: :not_acceptable unless request.format.json?
  end
end
