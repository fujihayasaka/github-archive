# typed: strict
# frozen_string_literal: true

class ModelsByok::CleanupSecretJob < GitHubModelsJob
  exempt_from_tenant_context_requirement

  queue_as :github_models_low_priority

  locked_by timeout: 1.minute, key: ->(job) do
    job.arguments.first[:kredz_key_name]
  end

  retry_on Secrets::Error, attempts: 3, wait: :polynomially_longer

  sig { params(actor_id: T.nilable(Integer), org_id: Integer, kredz_key_name: String).void }
  def perform(actor_id:, org_id:, kredz_key_name:)
    return unless GitHub.models_enabled?

    actor = actor_id ? User.find_by(id: actor_id) : nil
    actor ||= User.staff_user

    Secrets.delete(
      name: kredz_key_name,
      app: ModelsByok::CustomKey.integration_app,
      owner: Organization.find(org_id),
      actor: actor,
    )
  end
end
