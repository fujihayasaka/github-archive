# typed: strict
# frozen_string_literal: true

module Copilot
  module ChatAttachments
    class CleanupJob < CopilotJob
      exempt_from_tenant_context_requirement

      queue_as :background_destroy

      locked_by timeout: 1.minute, key: ->(job) do
        attachment_id = T.let(job.arguments.first, Integer)
        attachment_id.to_s
      end

      retry_on Storage::Uploadable::DeletionError, attempts: 3, wait: :polynomially_longer

      DOGSTATS_PREFIX = "copilot.chat_attachments.cleanup_job"

      sig { params(attachment_id: Integer).void }
      def perform(attachment_id)
        begin
          attachment = ::Copilot::ChatAttachment.find(attachment_id)
        rescue ActiveRecord::RecordNotFound
          GitHub.logger.warn("Copilot chat attachment not found", "gh.copilot.chat_attachment.id": attachment_id)
          GitHub.dogstats.increment("#{DOGSTATS_PREFIX}.record_not_found")
          return
        end

        GitHub.logger.with_named_tags(
          "gh.copilot.chat_attachment.id": attachment_id,
        ) do
          with_write { attachment.destroy! }

          GitHub.logger.info("Destroyed copilot chat attachment")
          GitHub.dogstats.increment("#{DOGSTATS_PREFIX}.deleted_attachments")
        end
      end
    end
  end
end
