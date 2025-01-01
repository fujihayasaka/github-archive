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
        GitHub.logger.with_named_tags("gh.copilot.chat_attachment.id": attachment_id) do
          begin
            attachment = ::Copilot::ChatAttachment.includes(:copilot_space_resources).find(attachment_id)
          rescue ActiveRecord::RecordNotFound
            GitHub.logger.warn("Copilot chat attachment not found")
            GitHub.dogstats.increment("#{DOGSTATS_PREFIX}.record_not_found")
            return
          end

          # Do not delete the Chat Attachment if it is associated with a Spaces Resource.
          if attachment.copilot_space_resources.any?
            GitHub.logger.info(
              "Skipped destroying copilot chat attachment due to being associated with a copilot space resource",
              "gh.copilot.custom_copilot_resource.ids": attachment.copilot_space_resources.map(&:id),
            )
            return
          end

          with_write { attachment.destroy! }

          GitHub.logger.info("Destroyed copilot chat attachment")
          GitHub.dogstats.increment("#{DOGSTATS_PREFIX}.deleted_attachments")
        end
      end
    end
  end
end
