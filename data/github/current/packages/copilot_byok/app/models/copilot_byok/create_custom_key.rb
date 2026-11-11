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
        models: T::Array[T.any({ name: T.nilable(String), slug: String }, { slug: String })],
        deployment_url: T.nilable(String),
        access_key: T.nilable(String)
      ).returns(Result)
    end
    def self.call(owner:, actor:, provider:, name:, api_key:, models: [], deployment_url: nil, access_key: nil)
      new(owner: owner, actor: actor, provider: provider, name: name, api_key: api_key, models: models,
        deployment_url: deployment_url, access_key: access_key).call
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

    sig do
      params(
        owner: T.any(Business, Organization),
        actor: User,
        provider: T.any(String, Symbol),
        name: T.nilable(String),
        api_key: T.nilable(String),
        models: T::Array[T.any({ name: T.nilable(String), slug: String }, { slug: String })],
        deployment_url: T.nilable(String),
        access_key: T.nilable(String)
      ).void
    end
    def initialize(owner:, actor:, provider:, name:, api_key:, models:, deployment_url:, access_key:)
      @owner = owner
      @actor = actor
      @provider = T.let(provider.to_s.downcase.to_sym, Symbol)
      @models = models
      @name = name
      @api_key = api_key
      @deployment_url = deployment_url
      @access_key = access_key
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
      validate_models
    end

    sig { returns T.nilable(String) }
    def validate_models
      return "At least one model must be provided" if @models.empty?

      given_slugs = @models.map { |m| m[:slug] }.compact
      given_names = @models.map { |m| m[:name] }.compact
      unless given_slugs.uniq.size == given_slugs.size && given_names.uniq.size == given_names.size
        return "Duplicate custom model given"
      end

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
      @owner.copilot_custom_keys.create!(base_custom_key_attributes.merge(deployment_url: @deployment_url))
    end

    sig { returns T::Array[T::Hash[Symbol, T.untyped]] }
    def custom_models_attributes
      @models.map do |model|
        attrs = { name: model[:name], slug: model[:slug], **copilot_chat_enabled_attrs }
        attrs[:capability_attributes] = build_capability_attributes(model) if has_capability_data?(model)
        attrs
      end
    end

    sig { returns T::Hash[Symbol, T.untyped] }
    def base_custom_key_attributes
      {
        name: @name,
        provider: @provider,
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
      access_key_index = part_indices[:access_key]
      api_key_index = part_indices[:api_key]
      parts = T.let([], T::Array[String])
      parts[access_key_index] = @access_key if access_key_index && @access_key
      parts[api_key_index] = @api_key if api_key_index && @api_key
      if parts.empty?
        nil
      else
        CustomKey.embed_multi_part_value(parts, owner: @owner)
      end
    end
  end
end
