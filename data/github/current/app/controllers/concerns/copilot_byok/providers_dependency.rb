# typed: true
# frozen_string_literal: true

module CopilotByok::ProvidersDependency
  extend ActiveSupport::Concern
  extend T::Helpers

  include GitHub::Memoizer

  abstract!

  requires_ancestor { ApplicationController }

  included do
    T.bind(self, T.class_of(ApplicationController))

    before_action :require_valid_provider
    before_action :require_api_key
  end

  private

  sig { abstract.returns(T.any(Business, Organization)) }
  def api_key_owner; end

  sig { returns T.nilable(CopilotByok::CustomKey) }
  memoize def custom_key
    api_key_owner.copilot_custom_keys.find(params[:custom_key_id]) if params[:custom_key_id]
  end

  def require_api_key
    if decrypted_api_key.nil?
      render json: { message: "Unable to retrieve API key" }, status: :internal_server_error
    end
  end

  def require_valid_provider
    if provider.nil?
      return render json: { message: "Provider is required" }, status: :unprocessable_entity
    end

    unless CopilotByok::CustomKey.valid_provider_for?(api_key_owner, T.must(provider).to_sym)
      render json: { message: "Invalid provider '#{provider}'" }, status: :unprocessable_entity
    end
  end

  sig { returns(T.nilable(String)) }
  memoize def decrypted_api_key
    CopilotByok::CustomKey.decrypt_api_key(params[:api_key], owner: api_key_owner, custom_key: custom_key)
  end

  sig { returns T.nilable(String) }
  memoize def provider
    custom_key&.provider || params[:provider]
  end

  sig { returns T.nilable(T::Array[CopilotByok::Types::SelectorCustomModel]) }
  def fetch_provider_models
    decrypted_api_key = T.must_because(self.decrypted_api_key) { "#require_api_key ensures non-nil" }
    case provider.to_s.downcase
    when "openai"
      CopilotByok::Providers::OpenAI.fetch_models(decrypted_api_key)
    when "openaicompatible"
      CopilotByok::Providers::OpenAICompatible.fetch_models(params[:base_url], decrypted_api_key)
    when "anthropic"
      CopilotByok::Providers::Anthropic.fetch_models(decrypted_api_key)
    when "googleaistudio"
      CopilotByok::Providers::GoogleAiStudio.fetch_models(decrypted_api_key)
    when "xai"
      CopilotByok::Providers::Xai.fetch_models(decrypted_api_key)
    end
  end
end
