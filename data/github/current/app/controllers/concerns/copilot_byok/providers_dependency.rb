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
    before_action :require_aws_access_key
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
      noun = aws_bedrock? ? "AWS secret access key" : "API key"
      render json: { message: "Unable to retrieve #{noun}" }, status: :internal_server_error
    end
  end

  def require_aws_access_key
    return unless aws_bedrock?
    if decrypted_aws_access_key.nil?
      render json: { message: "Unable to retrieve AWS access key" }, status: :internal_server_error
    end
  end

  def require_valid_provider
    provider = self.provider
    if provider.nil?
      return render json: { message: "Provider is required" }, status: :unprocessable_entity
    end

    unless CopilotByok::CustomKey.valid_provider_for?(api_key_owner, provider)
      render json: { message: "Invalid provider '#{provider}'" }, status: :unprocessable_entity
    end
  end

  sig { returns T.nilable(T::Boolean) }
  memoize def multi_part_secret?
    custom_key&.multi_part_secret? || (params[:api_key].present? && params[:access_key].present?)
  end

  sig { returns T.nilable(T::Array[String]) }
  memoize def decrypted_api_key_parts
    return unless multi_part_secret?
    part_indices = CopilotByok::CustomKey::MULTI_PART_ENCRYPTED_SECRET_VALUE_INDICES_BY_PROVIDER[provider]
    return unless part_indices
    parts = CopilotByok::CustomKey.build_parts_for_embedding_multi_part_value(part_indices,
      access_key: params[:access_key], api_key: params[:api_key])
    CopilotByok::CustomKey.decrypt_multi_part_api_key(parts, owner: api_key_owner, custom_key: custom_key)
  end

  sig { returns(T.nilable(String)) }
  memoize def decrypted_api_key
    if multi_part_secret?
      parts = decrypted_api_key_parts
      indices = multi_part_secret_value_indices
      return unless parts && indices

      api_key_index = indices[:api_key]
      parts[api_key_index] if api_key_index
    else
      CopilotByok::CustomKey.decrypt_api_key(params[:api_key], owner: api_key_owner, custom_key: custom_key)
    end
  end

  sig { returns T.nilable(T::Hash[Symbol, Integer]) }
  def multi_part_secret_value_indices
    CopilotByok::CustomKey::MULTI_PART_ENCRYPTED_SECRET_VALUE_INDICES_BY_PROVIDER[provider]
  end

  sig { returns(T.nilable(String)) }
  memoize def decrypted_aws_access_key
    parts = decrypted_api_key_parts
    indices = multi_part_secret_value_indices
    return unless parts && indices

    access_key_index = indices[:access_key]
    parts[access_key_index] if access_key_index
  end

  sig { returns T.nilable(Symbol) }
  memoize def provider
    (custom_key&.provider || params[:provider]&.downcase)&.to_sym
  end

  sig { returns T::Boolean }
  memoize def aws_bedrock?
    provider == :awsbedrock
  end

  sig { returns String }
  def invalid_api_key_message
    aws_bedrock? ? "Invalid secret access key" : "Invalid API key"
  end

  sig { returns T.nilable(T::Array[CopilotByok::Types::SelectorCustomModel]) }
  def fetch_provider_models
    decrypted_api_key = T.must_because(self.decrypted_api_key) { "#require_api_key ensures non-nil" }
    case provider
    when :openai
      CopilotByok::Providers::OpenAI.fetch_models(decrypted_api_key)
    when :openaicompatible
      CopilotByok::Providers::OpenAICompatible.fetch_models(params[:base_url], decrypted_api_key)
    when :anthropic
      CopilotByok::Providers::Anthropic.fetch_models(decrypted_api_key)
    when :googleaistudio
      CopilotByok::Providers::GoogleAiStudio.fetch_models(decrypted_api_key)
    when :xai
      CopilotByok::Providers::Xai.fetch_models(decrypted_api_key)
    when :awsbedrock
      decrypted_aws_access_key = T.must_because(self.decrypted_aws_access_key) do
        "#require_aws_access_key ensures non-nil"
      end
      CopilotByok::Providers::AwsBedrock.fetch_models(access_key: decrypted_aws_access_key,
        secret_access_key: decrypted_api_key, region: params[:region])
    end
  end
end
