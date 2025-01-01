# typed: strict
# frozen_string_literal: true

class ModelsByok::DeleteCustomKeyJob < GitHubModelsJob
  exempt_from_tenant_context_requirement

  queue_as :github_models_low_priority

  locked_by timeout: 1.minute, key: ->(job) do
    job.arguments.first[:custom_key_id]
  end

  class DeletionError < StandardError; end

  sig { params(custom_key_id: Integer, actor_id: Integer).void }
  def perform(custom_key_id:, actor_id:)
    return unless GitHub.models_enabled?

    custom_key = ModelsByok::CustomKey.find_by(id: custom_key_id)
    return unless custom_key

    actor = User.find_by(id: actor_id) || User.staff_user
    custom_models = load_custom_models_for(custom_key)

    errors = delete_org_access_rules(custom_key, actor: actor, custom_models: custom_models)
    raise DeletionError, errors.to_sentence if errors.any?

    errors = delete_custom_models(custom_models, actor: actor)
    raise DeletionError, errors.to_sentence if errors.any?

    errors = delete_custom_key(custom_key, actor: actor)
    raise DeletionError, errors.to_sentence if errors.any?
  end

  private

  sig { params(custom_key: ModelsByok::CustomKey).returns(T::Array[ModelsByok::CustomModel]) }
  def load_custom_models_for(custom_key)
    result = ModelsByok::CustomModel.for_custom_key(custom_key).to_a

    GitHub::PrefillAssociations.prefill_associations(result, :custom_key, available_records: [custom_key])

    # Load `organization` relation since it'll be used in audit log events:
    GitHub::PrefillAssociations.prefill_associations(result, :organization)

    result
  end

  sig { params(custom_key: ModelsByok::CustomKey, actor: User).returns(T::Array[String]) }
  def delete_custom_key(custom_key, actor:)
    custom_key.actor = actor
    with_write { custom_key.destroy }
    custom_key.destroyed? ? [] : custom_key.errors.full_messages
  end

  sig { params(custom_models: T::Array[ModelsByok::CustomModel], actor: User).returns(T::Array[String]) }
  def delete_custom_models(custom_models, actor:)
    errors = []

    ModelsByok::CustomModel.transaction do
      custom_models.each do |custom_model|
        custom_model.actor = actor
        with_write { custom_model.destroy }
        errors.concat(custom_model.errors.full_messages) unless custom_model.destroyed?
      end
    end

    errors
  end

  sig do
    params(custom_key: ModelsByok::CustomKey, actor: User, custom_models: T::Array[ModelsByok::CustomModel])
      .returns(T::Array[String])
  end
  def delete_org_access_rules(custom_key, actor:, custom_models:)
    rules = GitHubModels::OrganizationAccessRule.for_custom_key_or_its_models(custom_key, custom_models.map(&:id))
    errors = []

    # Prefill relations that will be used in audit log events, to avoid n+1 queries:
    GitHub::PrefillAssociations.prefill_associations(rules, :custom_key, available_records: [custom_key])
    GitHub::PrefillAssociations.prefill_associations(rules, :custom_model, available_records: custom_models)

    GitHubModels::OrganizationAccessRule.transaction do
      rules.each do |rule|
        rule.actor = actor
        with_write { rule.destroy }
        errors.concat(rule.errors.full_messages) unless rule.destroyed?
      end
    end

    errors
  end
end
