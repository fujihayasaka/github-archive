# typed: true
# frozen_string_literal: true

class Orgs::CopilotSettings::ByokProviderModelsController < Orgs::Controller
  include ApplicationController::JsonDependency
  include ApplicationController::VerifiedFetchDependency

  before_action :organization_admin_required
  before_action :copilot_required
  before_action :parse_json_params

  include CopilotByok::ProvidersDependency

  # Allow making requests to this endpoint from React apps using the `verifiedFetch` function:
  allow_verified_fetch only: [:create]

  def create
    custom_key = self.custom_key
    provider_models = fetch_provider_models

    json = if custom_key && provider_models.present?
      custom_key.reconcile_custom_models_with_provider(provider_models)
    elsif custom_key # Just return the custom models associated with the custom key
      custom_key.custom_models.map(&:to_selector_model)
    else
      provider_models || []
    end

    render json: json
  rescue CopilotByok::Providers::UnauthorizedError
    render json: { message: invalid_api_key_message }, status: :unauthorized
  rescue CopilotByok::Providers::InvalidURLError
    render json: { message: "Invalid base API URL" }, status: :unprocessable_entity
  end

  private

  sig { override.returns(::Organization) }
  def api_key_owner
    T.cast(this_organization, ::Organization)
  end
end
