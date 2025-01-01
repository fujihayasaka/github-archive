# typed: strict
# frozen_string_literal: true

class CopilotByok::DeleteCustomKeyJob < CopilotJob # rubocop:disable GitHub/KubeJobsRetryOnDirtyExit
  # Don't need a #retry_on_dirty_exit in this job because the parent class, `CopilotJob`, includes it.
  exempt_from_tenant_context_requirement

  locked_by timeout: 1.minute, key: ->(job) do
    job.arguments.first[:custom_key_id]
  end

  queue_as :copilot

  class DeletionError < StandardError; end

  sig { params(custom_key_id: Integer, actor_id: Integer).void }
  def perform(custom_key_id:, actor_id:)
    return unless GitHub.copilot_enabled?

    custom_key = CopilotByok::CustomKey.find_by(id: custom_key_id)
    return unless custom_key

    actor = User.find_by(id: actor_id) || User.staff_user
    custom_models = load_custom_models_for(custom_key)

    errors = delete_custom_models(custom_models, actor: actor)
    raise DeletionError, errors.to_sentence if errors.any?

    errors = delete_custom_key(custom_key, actor: actor)
    raise DeletionError, errors.to_sentence if errors.any?
  end

  private

  sig { params(custom_key: CopilotByok::CustomKey).returns(T::Array[CopilotByok::CustomModel]) }
  def load_custom_models_for(custom_key)
    result = CopilotByok::CustomModel.for_custom_key(custom_key).to_a

    GitHub::PrefillAssociations.prefill_associations(result, :custom_key, available_records: [custom_key])

    # Load `organization` relation since it'll be used in audit log events:
    GitHub::PrefillAssociations.prefill_associations(result, :organization)

    result
  end

  sig { params(custom_key: CopilotByok::CustomKey, actor: User).returns(T::Array[String]) }
  def delete_custom_key(custom_key, actor:)
    custom_key.actor = actor
    with_write { custom_key.destroy }
    custom_key.destroyed? ? [] : custom_key.errors.full_messages
  end

  sig { params(custom_models: T::Array[CopilotByok::CustomModel], actor: User).returns(T::Array[String]) }
  def delete_custom_models(custom_models, actor:)
    errors = []

    CopilotByok::CustomModel.transaction do
      custom_models.each do |custom_model|
        custom_model.actor = actor
        with_write { custom_model.destroy }
        errors.concat(custom_model.errors.full_messages) unless custom_model.destroyed?
      end
    end

    errors
  end
end
