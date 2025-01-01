# typed: strict
# frozen_string_literal: true

module Copilot
  module ChatAttachments
    class MaintenanceJob < CopilotJob
      exempt_from_tenant_context_requirement

      queue_as :background_destroy

      locked_by timeout: 1.minute, key: DEFAULT_LOCK_PROC
      schedule interval: 1.day, condition: -> { GitHub.copilot_enabled? }

      gate_with_feature_flag :copilot_chat_attachments_maintenance_job

      sig { void }
      def perform
        Copilot::ChatAttachment.where("created_at < ?", 28.days.ago).in_batches(of: 100) do |attachments|
          GitHub.logger.info("Deleting stale copilot chat attachments", "gh.copilot.chat_attachments.destroy_count": attachments.size)

          attachments.each do |attachment|
            GitHub.logger.info("Scheduling a deletion of the copilot chat attachments", id: attachment.id)
            ::Copilot::ChatAttachments::CleanupJob.perform_later(attachment.id)
          end
        end
      end
    end
  end
end
