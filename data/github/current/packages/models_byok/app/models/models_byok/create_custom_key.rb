# typed: true
# frozen_string_literal: true

module ModelsByok
  class CreateCustomKey
    # Public: Create a custom key for the specified organization and associates one or more custom models with it,
    # for use with Copilot and GitHub Models.
    sig do
      params(
        org: Organization,
        actor: ::User,
        provider: T.any(String, Symbol),
        name: T.nilable(String),
        api_key: T.nilable(String),
        model_id: T.nilable(T.any(String, Integer)),
        models: T.nilable(T::Array[T.any({ name: T.nilable(String), slug: String }, { slug: String })]),
        deployment_url: T.nilable(String)
      ).returns(Result)
    end
    def self.call(org:, actor:, provider:, name:, api_key:, model_id: nil, models: nil, deployment_url: nil)
      new(org: org, actor: actor, provider: provider, name: name, api_key: api_key, model_id: model_id,
        models: models, deployment_url: deployment_url).call
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
        org: Organization,
        actor: ::User,
        provider: T.any(String, Symbol),
        name: T.nilable(String),
        api_key: T.nilable(String),
        model_id: T.nilable(T.any(String, Integer)),
        models: T.nilable(T::Array[T.any({ name: T.nilable(String), slug: String }, { slug: String })]),
        deployment_url: T.nilable(String)
      ).void
    end
    def initialize(org:, actor:, provider:, name:, api_key:, model_id:, models:, deployment_url:)
      @org = org
      @actor = actor
      @provider = provider.to_s.downcase.to_sym
      @model_id = model_id
      @models = models
      @name = name
      @api_key = api_key
      @deployment_url = deployment_url
    end

    sig { returns Result }
    def call
      error = validate
      return Result.failure(error) if error

      custom_key_or_error = create_key_and_models
      return Result.failure(custom_key_or_error) if custom_key_or_error.is_a?(String)

      error = create_secret(custom_key_or_error)
      return Result.failure(error) if error

      Result.success(custom_key_or_error)
    end

    private

    sig { returns T.nilable(String) }
    def validate
      case @provider
      when :azureai then validate_azure_ai
      when :openai then validate_openai
      else
        "Invalid provider '#{@provider}'"
      end
    end

    sig { returns T.nilable(String) }
    def validate_azure_ai
      return "No model id submitted" if @model_id.blank?
      nil
    end

    sig { returns T.nilable(String) }
    def validate_openai
      return "At least one model must be provided" if !@models.is_a?(Array) || @models.empty?

      given_slugs = @models.map { |m| m[:slug] }.compact
      given_names = @models.map { |m| m[:name] }.compact
      unless given_slugs.uniq.size == given_slugs.size && given_names.uniq.size == given_names.size
        return "Duplicate custom model given"
      end

      nil
    end

    sig { returns T.any(String, CustomKey) }
    def create_key_and_models
      @provider == :azureai ? create_azureai : create_openai
    rescue ActiveRecord::RecordInvalid => e
      e.record.errors.full_messages.to_sentence
    end

    sig { params(custom_key: CustomKey).returns(T.nilable(String)) }
    def create_secret(custom_key)
      unless custom_key.create_secret(actor: @actor, api_key: T.must(@api_key))
        custom_key.destroy
        "Failed to create custom key"
      end
    end

    sig { returns CustomKey }
    def create_azureai
      ModelsByok::CustomKey.transaction do
        @org.models_custom_keys.create!(
          name: @name,
          provider: @provider,
          deployment_url: @deployment_url,
          custom_models_attributes: [{ name: @model_id, slug: @model_id }],
        )
      end
    end

    sig { returns CustomKey }
    def create_openai
      ModelsByok::CustomKey.transaction do
        @org.models_custom_keys.create!(
          name: @name,
          provider: @provider,
          custom_models_attributes: (@models || []).map { |model| { name: model[:name], slug: model[:slug] } },
        )
      end
    end
  end
end
