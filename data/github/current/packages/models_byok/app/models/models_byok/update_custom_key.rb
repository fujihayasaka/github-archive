# typed: true
# frozen_string_literal: true

module ModelsByok
  class UpdateCustomKey
    class Error < StandardError; end

    sig do
      params(
        custom_key: CustomKey,
        actor: User,
        name: T.nilable(String),
        deployment_url: T.nilable(String),
        models: T.nilable(T::Array[T.any({ name: T.nilable(String), id: String }, { slug: String })])
      ).returns(T.nilable(Error))
    end
    def self.call(custom_key:, actor:, name: nil, deployment_url: nil, models: nil)
      new(custom_key: custom_key, actor: actor, name: name, deployment_url: deployment_url, models: models).call
    end

    sig do
      params(
        custom_key: CustomKey,
        actor: User,
        name: T.nilable(String),
        deployment_url: T.nilable(String),
        models: T.nilable(T::Array[T.any({ name: T.nilable(String), id: String }, { slug: String })])
      ).void
    end
    def initialize(custom_key:, actor:, name:, deployment_url:, models:)
      @custom_key = custom_key
      @org_id = custom_key.organization_id
      @actor = actor
      @custom_key.actor = actor
      @name = name
      @deployment_url = deployment_url
      @models = models
    end

    sig { returns T.nilable(Error) }
    def call
      ModelsByok::CustomKey.transaction do
        @custom_key.update!(build_custom_key_attributes)
      end

      nil
    rescue ActiveRecord::RecordInvalid => e
      Error.new(e.record.errors.full_messages.to_sentence)
    end

    private

    sig { returns T::Array[CustomModel] }
    def existing_custom_models
      return @existing_custom_models if @existing_custom_models
      result = @custom_key.custom_models.to_a

      # Load `organization` relation since it'll be used to emit audit log events:
      GitHub::PrefillAssociations.prefill_associations(result, :organization,
        available_records: [@custom_key.organization])

      @existing_custom_models = result
    end

    sig { returns T::Array[Integer] }
    def existing_custom_model_ids
      @existing_custom_model_ids ||= existing_custom_models.map(&:id)
    end

    sig { returns T::Hash[Symbol, T.untyped] }
    def build_custom_key_attributes
      attributes = { custom_models_attributes: [] }
      attributes[:name] = @name unless @name.nil?
      attributes[:deployment_url] = @deployment_url unless @deployment_url.nil?
      set_attributes(attributes)
    end

    sig { params(attributes: T::Hash[Symbol, T.untyped]).returns(T::Hash[Symbol, T.untyped]) }
    def set_attributes(attributes)
      if @models.kind_of?(Array)
        incoming_ids = []
        updates = @models.filter_map do |model|
          if model[:id].present?
            incoming_ids << model[:id]
            { id: model[:id], name: model[:name] }
          else
            { slug: model.fetch(:slug), name: model[:name] }
          end
        end

        to_destroy = existing_custom_model_ids - incoming_ids
        delete_custom_models_and_their_org_access_rules(to_destroy)

        attributes[:custom_models_attributes] += updates
      end
      attributes
    end

    sig { params(custom_model_ids: T::Array[Integer]).void }
    def delete_custom_models_and_their_org_access_rules(custom_model_ids)
      return if custom_model_ids.empty?

      delete_org_access_rules_for_custom_models(custom_model_ids)
      delete_custom_models(custom_model_ids.to_set)
    end

    sig { params(custom_model_ids: T::Array[Integer]).void }
    def delete_org_access_rules_for_custom_models(custom_model_ids)
      rules = GitHubModels::OrganizationAccessRule.for_org(@org_id).for_custom_model(custom_model_ids)
        .includes(:custom_model) # load custom_model relation since it'll be used to emit audit log events
        .to_a
      return if rules.empty?

      GitHubModels::OrganizationAccessRule.transaction do
        rules.each do |rule|
          rule.actor = @actor
          rule.destroy!
        end
      end
    end

    sig { params(custom_model_ids: T::Set[Integer]).void }
    def delete_custom_models(custom_model_ids)
      custom_models = existing_custom_models.select { |custom_model| custom_model_ids.include?(custom_model.id) }

      ModelsByok::CustomModel.transaction do
        custom_models.each do |custom_model|
          custom_model.actor = @actor
          custom_model.destroy!
        end
      end
    end
  end
end
