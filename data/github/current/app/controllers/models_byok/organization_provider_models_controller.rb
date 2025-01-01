# typed: true
# frozen_string_literal: true

class ModelsByok::OrganizationProviderModelsController < Orgs::Controller
  include ApplicationController::JsonDependency
  include ApplicationController::VerifiedFetchDependency

  before_action :require_feature
  before_action :organization_admin_required
  before_action :github_models_required
  before_action :parse_json_params
  before_action :require_existing_provider
  before_action :require_openai

  # Allow making requests to this endpoint from React apps using the `verifiedFetch` function:
  allow_verified_fetch only: [:create]

  def create
    render json: ModelsByok::Providers::OpenAI.fetch_models(decrypted_api_key)
  rescue ModelsByok::Providers::OpenAI::UnauthorizedError
    render json: { message: "Invalid OpenAI API key" }, status: :unauthorized
  end

  private

  sig { returns(::Organization) }
  memoize def org
    T.cast(this_organization, ::Organization)
  end

  def require_feature
    render_404 unless org.feature_enabled?(:github_models_byok)
  end

  def provider
    params[:provider]
  end

  def require_existing_provider
    unless ModelsByok::CustomKey.providers.key?(provider)
      render json: { message: "Invalid provider '#{provider}'" }, status: :unprocessable_entity
    end
  end

  def require_openai
    unless provider == "openai"
      render json: { message: "Only OpenAI provider is supported for fetching models" }, status: :unprocessable_entity
    end
  end

  sig { returns String }
  def decrypted_api_key
    encoded_api_key = ModelsByok::CustomKey.embed_value(params[:api_key], owner: org)
    ModelsByok::CustomKey.decrypt_secret(encoded_api_key, owner: org)
  end
end
