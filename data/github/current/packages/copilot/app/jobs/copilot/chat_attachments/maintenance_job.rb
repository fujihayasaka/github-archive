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
        # Do not include Chat Attachments associated with Spaces Resources.
        chat_attachments_query = Copilot::ChatAttachment.where(created_at: ...28.days.ago)
          .left_outer_joins(:copilot_space_resources)
          .where(custom_copilot_resources: { id: nil })
          .select(:created_at, :id)

        chat_attachments_query.in_batches(of: 100, cursor: [:created_at, :id]) do |chat_attachments|
          GitHub.logger.info("Deleting stale copilot chat attachments", "gh.copilot.chat_attachments.destroy_count": chat_attachments.size)

          chat_attachments.each do |chat_attachment|
            GitHub.logger.info("Scheduling a deletion of the copilot chat attachments", id: chat_attachment.id)
            ::Copilot::ChatAttachments::CleanupJob.perform_later(chat_attachment.id)
          end
        end
      end
    end
  end
end
