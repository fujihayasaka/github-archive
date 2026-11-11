# typed: strict
# frozen_string_literal: true

module CopilotByok
  class CreateCustomKey
    include GitHub::Memoizer
    include CopilotByok::Concerns::CapabilityAttributesBuilder

    # Public: Create a custom key for the specified organization or enterprise and associates one or more custom
    # models with it, for use with Copilot.
    sig do
      params(
        owner: T.any(Business, Organization),
        actor: User,
        provider: T.any(String, Symbol),
        name: T.nilable(String),
        api_key: T.nilable(String),
        models: T::Array[T::Hash[Symbol, T.untyped]],
        deployment_url: T.nilable(String),
        access_key: T.nilable(String),
        provider_data: T.nilable(Types::CustomKeyProviderData)
      ).returns(Result)
    end
    def self.call(owner:, actor:, provider:, name:, api_key:, models: [], deployment_url: nil, access_key: nil, provider_data: nil)
      new(owner: owner, actor: actor, provider: provider, name: name, api_key: api_key, models: models,
        deployment_url: deployment_url, access_key: access_key, provider_data: provider_data).call
    end

    class Result
      sig { params(custom_key: CustomKey).returns(Result) }
      def self.success(custom_key)
        new(custom_key: custom_key, error: nil)
      end

      sig { params(error: String).returns(Result) }
      def self.failure(error)
        new(custom_key: nil, error: error)
      end

      # Public: Only set when the custom key and custom model(s) were created successfully.
      sig { returns T.nilable(CustomKey) }
      attr_reader :custom_key

      # Public: Will be nil for a successful creation, otherwise contains an error message.
      sig { returns T.nilable(String) }
      attr_reader :error

      sig { params(custom_key: T.nilable(CustomKey), error: T.nilable(String)).void }
      def initialize(custom_key:, error:)
        @custom_key = custom_key
        @error = error
      end
    end

    class ModelProviderDataValidationResult
      sig { returns T.nilable(String) }
      attr_reader :error

      sig { returns T.nilable(CopilotByok::ProviderData::CustomModel::AwsBedrock) }
      attr_reader :provider_data

      sig do
        params(
          error: T.nilable(String),
          provider_data: T.nilable(CopilotByok::ProviderData::CustomModel::AwsBedrock)
        ).void
      end
      def initialize(error: nil, provider_data: nil)
        @error = error
        @provider_data = provider_data
      end
    end

    sig do
      params(
        owner: T.any(Business, Organization),
        actor: User,
        provider: T.any(String, Symbol),
        name: T.nilable(String),
        api_key: T.nilable(String),
        models: T::Array[T::Hash[Symbol, T.untyped]],
        deployment_url: T.nilable(String),
        access_key: T.nilable(String),
        provider_data: T.nilable(Types::CustomKeyProviderData)
      ).void
    end
    def initialize(owner:, actor:, provider:, name:, api_key:, models:, deployment_url:, access_key:, provider_data: nil)
      @owner = owner
      @actor = actor
      @provider = T.let(provider.to_s.downcase.to_sym, Symbol)
      @models = models
      @name = name
      @api_key = api_key
      @deployment_url = deployment_url
      @access_key = access_key
      @provider_data = provider_data
    end

    sig { returns Result }
    def call
      error = validate
      return Result.failure(error) if error

      custom_key_or_error = create_custom_key
      return Result.failure(custom_key_or_error) if custom_key_or_error.is_a?(String)

      Result.success(custom_key_or_error)
    end

    private

    sig { returns T.nilable(String) }
    def validate
      return "Invalid provider '#{@provider}'" unless CustomKey.available_providers_for(@owner).include?(@provider)
      return "Access key is required" if @provider == :awsbedrock && @access_key.blank?

      key_provider_data_error = validate_key_provider_data
      return key_provider_data_error if key_provider_data_error

      validate_models
    end

    sig { returns T.nilable(String) }
    def validate_key_provider_data
      case @provider
      when :awsbedrock
        return validate_aws_bedrock_key_provider_data
      when :openaicompatible
        return validate_openai_compatible_key_provider_data
      when :azureai
        return validate_azureai_key_provider_data
      else
        return "Provider #{@provider} should not have any provider-specific custom key data" if @provider_data
      end

      nil # custom key provider data is valid, no error
    end

    sig { returns T.nilable(String) }
    def validate_models_provider_data
      normalized_provider_data_by_models_index = T.let({},
        T::Hash[Integer, CopilotByok::ProviderData::CustomModel::AwsBedrock])

      @models.each_with_index do |model_data, i|
        provider_data = model_data[:provider_data]

        case @provider
        when :awsbedrock
          validation_result = validate_aws_bedrock_model_provider_data(provider_data)
          return validation_result.error if validation_result.error
          normalized_provider_data_by_models_index[i] = T.must(validation_result.provider_data)
        else
          return "Provider #{@provider} should not have any provider-specific custom model data" if provider_data
        end
      end

      @models = @models.map.with_index do |model_data, i|
        if normalized_provider_data_by_models_index.key?(i)
          model_data.merge(provider_data: normalized_provider_data_by_models_index[i])
        else
          model_data
        end
      end

      nil # custom model provider data is valid, no errors
    end

    sig { returns T.nilable(String) }
    def validate_aws_bedrock_key_provider_data
      case @provider_data
      when CopilotByok::ProviderData::CustomKey::AwsBedrock
        nil # custom key provider data is valid for AWS Bedrock, no error
      when Hash
        begin
          @provider_data = CopilotByok::ProviderData::CustomKey::AwsBedrock.build!(@provider_data)
        rescue => err
          return "Invalid AWS Bedrock provider data: #{err.message}"
        end
        nil # custom key provider data is valid for AWS Bedrock, no error
      else
        "Provider data is invalid for AWS Bedrock"
      end
    end

    # Private: Checks whether the given provider-specific data is valid for an AWS Bedrock custom model.
    sig do
      params(
        provider_data: T.nilable(T.any(
          CopilotByok::ProviderData::CustomModel::AwsBedrock,
          T::Hash[String, T.untyped]
        ))
      ).returns(ModelProviderDataValidationResult)
    end
    def validate_aws_bedrock_model_provider_data(provider_data)
      case provider_data
      when CopilotByok::ProviderData::CustomModel::AwsBedrock
        ModelProviderDataValidationResult.new(provider_data: provider_data)
      when Hash
        begin
          normalized_provider_data = CopilotByok::ProviderData::CustomModel::AwsBedrock.build!(provider_data)
          ModelProviderDataValidationResult.new(provider_data: normalized_provider_data)
        rescue => err
          ModelProviderDataValidationResult.new(error: "Invalid AWS Bedrock model provider data: #{err.message}")
        end
      else
        ModelProviderDataValidationResult.new(error: "Provider data is invalid for AWS Bedrock model")
      end
    end

    sig { returns T.nilable(String) }
    def validate_openai_compatible_key_provider_data
      case @provider_data
      when CopilotByok::ProviderData::CustomKey::OpenAICompatible
        nil # custom key provider data is valid for OpenAI Compatible, no error
      when Hash
        begin
          @provider_data = CopilotByok::ProviderData::CustomKey::OpenAICompatible.build!(@provider_data)
        rescue => err
          return "Invalid OpenAI-compatible provider data: #{err.message}"
        end
        nil # custom key provider data is valid for OpenAI Compatible, no error
      else
        "Provider data is invalid for OpenAI-compatible provider"
      end
    end

    sig { returns T.nilable(String) }
    def validate_azureai_key_provider_data
      # If provider_data is already set (future API calls), validate it
      if @provider_data
        case @provider_data
        when CopilotByok::ProviderData::CustomKey::MicrosoftFoundry
          nil # custom key provider data is valid for Microsoft Foundry, no error
        when Hash
          begin
            @provider_data = CopilotByok::ProviderData::CustomKey::MicrosoftFoundry.build!(@provider_data)
          rescue => err
            return "Invalid Microsoft Foundry provider data: #{err.message}"
          end
          nil # custom key provider data is valid for Microsoft Foundry, no error
        else
          "Provider data is invalid for Microsoft Foundry"
        end
      # If deployment_url parameter is set (current API calls), convert to provider_data
      elsif @deployment_url.present?
        @provider_data = CopilotByok::ProviderData::CustomKey::MicrosoftFoundry.new(
          deployment_url: @deployment_url
        )
        nil
      else
        "Deployment url must be set for a Microsoft Foundry custom key"
      end
    end

    sig { returns T.nilable(String) }
    def validate_models
      return "At least one model must be provided" if @models.empty?

      given_slugs = @models.map { |m| m[:slug] }.compact
      given_names = @models.map { |m| m[:name] }.compact
      unless given_slugs.uniq.size == given_slugs.size && given_names.uniq.size == given_names.size
        return "Duplicate custom model given"
      end

      models_provider_data_error = validate_models_provider_data
      return models_provider_data_error if models_provider_data_error

      nil
    end

    sig { returns T.any(String, CustomKey) }
    def create_custom_key
      CustomKey.transaction do
        @provider == :azureai ? create_azureai : create_generic
      end
    rescue ActiveRecord::RecordInvalid => e
      e.record.errors.full_messages.to_sentence
    end

    sig { returns CustomKey }
    def create_azureai
      # Only write to provider_data column
      @owner.copilot_custom_keys.create!(base_custom_key_attributes)
    end

    sig { returns T::Array[T::Hash[Symbol, T.untyped]] }
    def custom_models_attributes
      @models.map do |model|
        attrs = {
          name: model[:name],
          slug: model[:slug],
          provider_data: model[:provider_data],
          **copilot_chat_enabled_attrs,
        }
        attrs[:capability_attributes] = build_capability_attributes(model) if has_capability_data?(model)
        attrs
      end
    end

    sig { returns T::Hash[Symbol, T.untyped] }
    def base_custom_key_attributes
      {
        name: @name,
        provider: @provider,
        provider_data: @provider_data,
        actor: @actor,
        encrypted_secret_value: encrypted_secret_value,
        custom_models_attributes: custom_models_attributes,
      }
    end

    sig { returns CustomKey }
    def create_generic
      @owner.copilot_custom_keys.create!(base_custom_key_attributes)
    end

    sig { returns T::Hash[Symbol, T::Boolean] }
    def copilot_chat_enabled_attrs
      { copilot_chat_enabled: true }
    end

    sig { returns T.nilable(String) }
    memoize def encrypted_secret_value
      part_indices = CustomKey::MULTI_PART_ENCRYPTED_SECRET_VALUE_INDICES_BY_PROVIDER[@provider]
      if part_indices
        embed_multi_part_secret_value(part_indices)
      elsif @api_key
        CustomKey.embed_value(@api_key, owner: @owner)
      else
        nil
      end
    rescue
      # The model validation will catch this issue and log there
      # we dont want to tell a user what was wrong with the api key validation
      # to avoid an attack vector
      nil
    end

    sig { params(part_indices: T::Hash[Symbol, Integer]).returns(T.nilable(String)) }
    def embed_multi_part_secret_value(part_indices)
      parts = CustomKey.build_parts_for_embedding_multi_part_value(part_indices, access_key: @access_key,
        api_key: @api_key)
      if parts.empty?
        nil
      else
        CustomKey.embed_multi_part_value(parts, owner: @owner)
      end
    end
  end
end
