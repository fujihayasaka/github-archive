# typed: strict
# frozen_string_literal: true

module CopilotByok
  class UpdateCustomKey
    include GitHub::Memoizer
    include CopilotByok::Concerns::CapabilityAttributesBuilder

    class Error < StandardError; end

    sig do
      params(
        custom_key: CustomKey,
        actor: User,
        name: T.nilable(String),
        deployment_url: T.nilable(String),
        models: T.nilable(T::Array[T::Hash[Symbol, T.untyped]]),
        api_key: T.nilable(String),
        access_key: T.nilable(String),
        provider_data: T.nilable(Types::CustomKeyProviderData)
      ).returns(T.nilable(Error))
    end
    def self.call(custom_key:, actor:, name: nil, deployment_url: nil, models: nil, api_key: nil, access_key: nil, provider_data: nil)
      new(custom_key: custom_key, actor: actor, name: name, deployment_url: deployment_url, models: models,
        api_key: api_key, access_key: access_key, provider_data: provider_data).call
    end

    sig do
      params(
        custom_key: CustomKey,
        actor: User,
        name: T.nilable(String),
        deployment_url: T.nilable(String),
        models: T.nilable(T::Array[T::Hash[Symbol, T.untyped]]),
        api_key: T.nilable(String),
        access_key: T.nilable(String),
        provider_data: T.nilable(Types::CustomKeyProviderData)
      ).void
    end
    def initialize(custom_key:, actor:, name:, deployment_url:, models:, api_key:, access_key:, provider_data:)
      @custom_key = custom_key
      @actor = actor
      @custom_key.actor = actor
      @name = name
      @deployment_url = deployment_url
      @models = models
      @api_key = api_key
      @access_key = access_key
      @provider_data = provider_data
    end

    sig { returns T.nilable(Error) }
    def call
      validate

      CustomKey.transaction do
        @custom_key.update!(build_custom_key_attributes)
      end

      nil
    rescue ActiveRecord::RecordInvalid => e
      Error.new(e.record.errors.full_messages.to_sentence)
    rescue Error => e
      # Catch the specific Error we raise above
      e
    end

    private

    sig { void }
    def validate
      validate_key_provider_data
      validate_models
    end

    sig { void }
    def validate_key_provider_data
      # For Azure AI keys, also check if deployment_url is provided (current API)
      # and normalize it to provider_data
      if @custom_key.azureai? && (@provider_data || @deployment_url)
        validate_azureai_key_provider_data
        return
      end

      return unless @provider_data

      case @custom_key.provider
      when "awsbedrock"
        validate_aws_bedrock_key_provider_data
      when "openaicompatible"
        validate_openai_compatible_key_provider_data
      when "azureai"
        validate_azureai_key_provider_data
      else
        raise Error, "Provider #{@custom_key.provider} should not have any provider-specific custom key data"
      end
    end

    sig { void }
    def validate_models
      return unless @models

      given_slugs = @models.map { |m| m[:slug] }.compact
      given_names = @models.map { |m| m[:name] }.compact
      unless given_slugs.uniq.size == given_slugs.size && given_names.uniq.size == given_names.size
        raise Error, "Duplicate custom model given"
      end

      validate_models_provider_data
    end

    sig { void }
    def validate_models_provider_data
      return unless @models

      normalized_provider_data_by_models_index = T.let({},
        T::Hash[Integer, CopilotByok::ProviderData::CustomModel::AwsBedrock])

      @models.each_with_index do |model_data, i|
        provider_data = model_data[:provider_data]

        case @custom_key.provider
        when "awsbedrock"
          normalized_provider_data = validate_aws_bedrock_model_provider_data(provider_data, model_data: model_data)
          normalized_provider_data_by_models_index[i] = normalized_provider_data if normalized_provider_data
        else
          if provider_data
            raise Error, "Provider #{@custom_key.provider} should not have any provider-specific custom model data"
          end
        end
      end

      @models = @models.map.with_index do |model_data, i|
        if normalized_provider_data_by_models_index.key?(i)
          model_data.merge(provider_data: normalized_provider_data_by_models_index[i])
        else
          model_data
        end
      end
    end

    sig { void }
    def validate_aws_bedrock_key_provider_data
      case @provider_data
      when CopilotByok::ProviderData::CustomKey::AwsBedrock
        # custom key provider data is valid for AWS Bedrock, no error
      when Hash
        begin
          @provider_data = CopilotByok::ProviderData::CustomKey::AwsBedrock.build!(@provider_data)
        rescue => err
          raise Error, "Invalid AWS Bedrock provider data: #{err.message}"
        end
      else
        raise Error, "Missing provider-specific data for AWS Bedrock"
      end
    end

    sig { void }
    def validate_openai_compatible_key_provider_data
      case @provider_data
      when CopilotByok::ProviderData::CustomKey::OpenAICompatible
        # custom key provider data is valid for OpenAI-compatible provider, no error
      when Hash
        begin
          @provider_data = CopilotByok::ProviderData::CustomKey::OpenAICompatible.build!(@provider_data)
        rescue => err
          raise Error, "Invalid OpenAI-compatible provider data: #{err.message}"
        end
      else
        raise Error, "Missing provider-specific data for OpenAI-compatible provider"
      end
    end

    sig { void }
    def validate_azureai_key_provider_data
      # If provider_data is already set (future API calls), validate it
      if @provider_data
        case @provider_data
        when CopilotByok::ProviderData::CustomKey::MicrosoftFoundry
          # custom key provider data is valid for Microsoft Foundry, no error
        when Hash
          begin
            @provider_data = CopilotByok::ProviderData::CustomKey::MicrosoftFoundry.build!(@provider_data)
          rescue => err
            raise Error, "Invalid Microsoft Foundry provider data: #{err.message}"
          end
        else
          raise Error, "Invalid provider data for Microsoft Foundry"
        end
      # If deployment_url parameter is set (current API calls), convert to provider_data
      elsif @deployment_url.present?
        @provider_data = CopilotByok::ProviderData::CustomKey::MicrosoftFoundry.new(
          deployment_url: @deployment_url
        )
      else
        raise Error, "Deployment url must be set for a Microsoft Foundry custom key"
      end
    end

    sig do
      params(
        provider_data: T.nilable(T.any(
          CopilotByok::ProviderData::CustomModel::AwsBedrock,
          T::Hash[String, T.untyped]
        )),
        model_data: T::Hash[Symbol, T.untyped]
      ).returns(T.nilable(CopilotByok::ProviderData::CustomModel::AwsBedrock))
    end
    def validate_aws_bedrock_model_provider_data(provider_data, model_data:)
      case provider_data
      when CopilotByok::ProviderData::CustomModel::AwsBedrock
        provider_data
      when Hash
        begin
          CopilotByok::ProviderData::CustomModel::AwsBedrock.build!(provider_data)
        rescue => err
          raise Error, "Invalid AWS Bedrock model provider data: #{err.message}"
        end
      else
        if model_data[:id].nil? # if we're creating a new custom model
          raise Error, "Missing provider-specific data for AWS Bedrock model"
        end
      end
    end

    sig { returns T::Array[CustomModel] }
    memoize def existing_custom_models
      result = @custom_key.custom_models.to_a

      # Load relations that will be used to emit audit log events:
      GitHub::PrefillAssociations.prefill_associations(result, :organization,
        available_records: [@custom_key.organization])
      GitHub::PrefillAssociations.prefill_associations(result, :business,
        available_records: [@custom_key.business])

      result
    end

    sig { returns T::Array[Integer] }
    memoize def existing_custom_model_ids
      existing_custom_models.map(&:id)
    end

    sig { returns T::Hash[Symbol, T.untyped] }
    def build_custom_key_attributes
      attributes = { custom_models_attributes: [] }
      if should_update_encrypted_secret_value?
        attributes[:encrypted_secret_value] = encrypted_secret_value
      end
      attributes[:name] = @name unless @name.nil?

      # Update provider_data if provided
      if @provider_data
        attributes[:provider_data] = @provider_data
      end

      set_attributes(attributes)
    end

    sig { returns T.nilable(T::Boolean) }
    def should_update_encrypted_secret_value?
      return true if @api_key.present?
      @access_key.present? && @custom_key.awsbedrock?
    end

    sig { params(attributes: T::Hash[Symbol, T.untyped]).returns(T::Hash[Symbol, T.untyped]) }
    def set_attributes(attributes)
      if @models.kind_of?(Array)
        incoming_ids = []
        updates = @models.filter_map do |model|
          base_attrs = if model[:id].present?
            incoming_ids << model[:id]
            { id: model[:id] }
          else
            { slug: model[:slug] }
          end
          base_attrs[:name] = model[:name]
          base_attrs[:provider_data] = model[:provider_data] if model[:provider_data]

          if has_capability_data?(model)
            # Find existing capability if this is an update (model has an ID)
            existing_capability = if model[:id].present?
              existing_model = existing_custom_models.find { |m| m.id == model[:id] }
              existing_model&.capability
            end

            base_attrs[:capability_attributes] = build_capability_attributes(
              model,
              existing_capability: existing_capability
            )
          end

          base_attrs
        end

        to_destroy = existing_custom_model_ids - incoming_ids
        delete_custom_models(to_destroy.to_set)

        attributes[:custom_models_attributes] += updates
      end
      attributes
    end

    sig { params(custom_model_ids: T::Set[Integer]).void }
    def delete_custom_models(custom_model_ids)
      return if custom_model_ids.empty?

      custom_models = existing_custom_models.select { |custom_model| custom_model_ids.include?(custom_model.id) }

      CopilotByok::CustomModel.transaction do
        custom_models.each do |custom_model|
          custom_model.actor = @actor
          custom_model.destroy!
        end
      end
    end

    sig { returns T.nilable(String) }
    memoize def encrypted_secret_value
      owner = @custom_key.owner
      return nil unless owner.present?

      part_indices = CustomKey::MULTI_PART_ENCRYPTED_SECRET_VALUE_INDICES_BY_PROVIDER[@custom_key.provider.to_sym]
      if part_indices
        embed_multi_part_secret_value(part_indices, owner: owner)
      else
        CustomKey.embed_value(T.must(@api_key), owner: owner)
      end
    rescue
      # The model validation will catch this issue and log there
      # we dont want to tell a user what was wrong with the api key validation
      # to avoid an attack vector
      nil
    end

    sig do
      params(part_indices: T::Hash[Symbol, Integer], owner: T.any(Business, Organization)).returns(T.nilable(String))
    end
    def embed_multi_part_secret_value(part_indices, owner:)
      parts = CustomKey.build_parts_for_embedding_multi_part_value(part_indices, access_key: @access_key,
        api_key: @api_key, fallback_parts: @custom_key.encrypted_secret_value_parts)
      if parts.empty?
        nil
      else
        CustomKey.embed_multi_part_value(parts, owner: owner)
      end
    end
  end
end
