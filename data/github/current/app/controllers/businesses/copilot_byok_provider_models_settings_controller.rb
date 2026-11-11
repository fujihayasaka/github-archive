# typed: true
# frozen_string_literal: true

class Businesses::CopilotByokProviderModelsSettingsController < Businesses::BusinessController
  include ApplicationController::JsonDependency
  include ApplicationController::VerifiedFetchDependency

  before_action :dotcom_required
  before_action :business_owner_required
  before_action :business_not_downgraded_to_free_plan_required
  before_action :ensure_copilot_enabled
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
      custom_key.custom_models.map do |model|
        {
          slug: model.slug,
          createdAt: model.created_at.utc,
          selected: true, # Always selected since these are the custom models for the key
        }
      end
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

  sig { override.returns(Business) }
  def api_key_owner
    this_business
  end

  sig { returns(Copilot::Business) }
  memoize def copilot_business
    Copilot::Business.new(this_business)
  end

  sig { void }
  def ensure_copilot_enabled
    render_404 unless copilot_business.copilot_enabled?
  end
end
