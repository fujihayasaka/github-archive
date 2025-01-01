# typed: true
# frozen_string_literal: true

class ModelsByok::OrganizationProviderModelsController < Orgs::Controller
  include ApplicationController::JsonDependency
  include ApplicationController::VerifiedFetchDependency

  before_action :organization_admin_required
  before_action :github_models_required
  before_action :parse_json_params
  before_action :require_existing_provider
  before_action :require_api_key

  # Allow making requests to this endpoint from React apps using the `verifiedFetch` function:
  allow_verified_fetch only: [:create]

  def create
    decrypted_api_key = T.must_because(self.decrypted_api_key) { "#require_api_key ensures non-nil" }
    custom_key = self.custom_key
    is_open_ai = provider == "openai"

    provider_models = if is_open_ai
      open_ai_models(decrypted_api_key)
    elsif azure_open_ai? # Can only get a list of models from the Azure OpenAI Endpoint
      azure_open_ai_models(decrypted_api_key)
    elsif custom_key # Just return the custom models associated with the custom key
      custom_key.custom_models.map do |model|
        {
          slug: model.slug,
          createdAt: model.created_at.utc,
          selected: true, # Always selected since these are the custom models for the key
        }
      end
    else
      []
    end

    json = if custom_key && (is_open_ai || azure_open_ai?)
      custom_key.reconcile_custom_models_with_provider(provider_models)
    else
      provider_models
    end

    render json: json
  rescue ModelsByok::Providers::OpenAI::UnauthorizedError
    render json: { message: "Invalid OpenAI API key" }, status: :unauthorized
  rescue ModelsByok::Providers::AzureAI::UnauthorizedError
    render json: { message: "Invalid Azure API key or deployment URL" }, status: :unauthorized
  end

  private

  def open_ai_models(api_key)
    ModelsByok::Providers::OpenAI.fetch_models(api_key)
  end

  def azure_open_ai_models(api_key)
    ModelsByok::Providers::AzureAI.fetch_models(api_key, params[:deployment_url])
  end

  sig { returns(::Organization) }
  memoize def org
    T.cast(this_organization, ::Organization)
  end

  sig { returns T.nilable(String) }
  memoize def provider
    custom_key&.provider || params[:provider]
  end

  def require_existing_provider
    provider = self.provider
    if provider.nil? || !ModelsByok::CustomKey.providers.key?(provider)
      render json: { message: "Invalid provider '#{provider}'" }, status: :unprocessable_entity
    end
  end

  sig { returns(T.nilable(String)) }
  memoize def decrypted_api_key
    api_key = params[:api_key]
    encoded_api_key = if api_key.blank?
      custom_key&.fetch_secret(actor: current_user)
    else
      ModelsByok::CustomKey.embed_value(api_key, owner: org)
    end
    return if encoded_api_key.nil?
    ModelsByok::CustomKey.decrypt_secret(encoded_api_key, owner: org)
  end

  def require_api_key
    if decrypted_api_key.nil?
      render json: { message: "Unable to retrieve API key" }, status: :internal_server_error
    end
  end

  sig { returns T.nilable(ModelsByok::CustomKey) }
  memoize def custom_key
    org.models_custom_keys.find(params[:custom_key_id]) if params[:custom_key_id]
  end

  sig { returns T::Boolean }
  memoize def azure_open_ai?
    return false unless provider == "azureai"
    uri = URI.parse(params[:deployment_url]) rescue nil
    return false if uri.nil?
    uri.hostname&.downcase&.end_with?(ModelsByok::CustomKey::VALID_AZURE_OPENAI_HOSTNAME) || false
  end
end
