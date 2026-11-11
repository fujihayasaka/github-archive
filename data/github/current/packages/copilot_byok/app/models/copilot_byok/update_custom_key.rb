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
        models: T.nilable(T::Array[T.any({ name: T.nilable(String), id: String }, { slug: String })]),
        api_key: T.nilable(String)
      ).returns(T.nilable(Error))
    end
    def self.call(custom_key:, actor:, name: nil, deployment_url: nil, models: nil, api_key: nil)
      new(custom_key: custom_key, actor: actor, name: name, deployment_url: deployment_url, models: models, api_key: api_key).call
    end

    sig do
      params(
        custom_key: CustomKey,
        actor: User,
        name: T.nilable(String),
        deployment_url: T.nilable(String),
        models: T.nilable(T::Array[T.any({ name: T.nilable(String), id: String }, { slug: String })]),
        api_key: T.nilable(String)
      ).void
    end
    def initialize(custom_key:, actor:, name:, deployment_url:, models:, api_key:)
      @custom_key = custom_key
      @actor = actor
      @custom_key.actor = actor
      @name = name
      @deployment_url = deployment_url
      @models = models
      @api_key = api_key
    end

    sig { returns T.nilable(Error) }
    def call
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
      if @api_key.present?
        attributes[:encrypted_secret_value] = encrypted_secret_value
      end
      attributes[:name] = @name unless @name.nil?
      attributes[:deployment_url] = @deployment_url unless @deployment_url.nil?
      set_attributes(attributes)
    end

    sig { params(attributes: T::Hash[Symbol, T.untyped]).returns(T::Hash[Symbol, T.untyped]) }
    def set_attributes(attributes)
      if @models.kind_of?(Array)
        incoming_ids = []
        updates = @models.filter_map do |model|
          base_attrs = if model[:id].present?
            incoming_ids << model[:id]
            { id: model[:id], name: model[:name] }
          else
            { slug: model.fetch(:slug), name: model[:name] }
          end

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
      CustomKey.embed_value(T.must(@api_key), owner: owner)
    rescue
      # The model validation will catch this issue and log there
      # we dont want to tell a user what was wrong with the api key validation
      # to avoid an attack vector
      nil
    end
  end
end
