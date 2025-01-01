# typed: strict
# frozen_string_literal: true

module GitHubModels
  class AttachmentsCleanupJob < GitHubModelsJob
    exempt_from_tenant_context_requirement

    queue_as :github_models_low_priority

    locked_by timeout: 1.minute, key: ->(job) do
      attachment_id = T.let(job.arguments.first, Integer)
      attachment_id.to_s
    end

    retry_on Storage::Uploadable::DeletionError, attempts: 3, wait: :polynomially_longer

    sig { params(attachment_id: Integer).void }
    def perform(attachment_id)
      attachment = ::GitHubModels::Attachment.find(attachment_id)

      GitHub.logger.with_named_tags(
        "gh.github_models.attachment.id": attachment_id,
      ) do
        with_write { attachment.destroy! }

        GitHub.logger.info("Destroyed github models attachment")
      end
    end
  end
end
