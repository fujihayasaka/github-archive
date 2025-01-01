# typed: strict
# frozen_string_literal: true

module Copilot
  module ChatAttachments
    class CleanupForThreadsJob < CopilotJob
      exempt_from_tenant_context_requirement

      queue_as :background_destroy

      gate_with_feature_flag :copilot_chat_attachments_cleanup_for_threads

      DOGSTATS_PREFIX = "copilot.chat_attachments.cleanup_for_threads_job"

      sig { params(thread_ids: T::Array[String]).void }
      def perform(thread_ids)
        thread_ids.each do |thread_id|
          GitHub.logger.info("Deleting copilot chat attachments for thread", "gh.copilot.chat_attachments.thread": thread_id)
          Copilot::ChatAttachment.where(thread_id: thread_id).in_batches(of: 100) do |attachments|
            GitHub.logger.info("Deleting copilot chat attachments", "gh.copilot.chat_attachments.destroy_count": attachments.size)

            attachments.each do |attachment|
              GitHub.logger.info("Scheduling a deletion of the copilot chat attachments", id: attachment.id)
              ::Copilot::ChatAttachments::CleanupJob.perform_later(attachment.id)
            end
          end

          GitHub.dogstats.increment("#{DOGSTATS_PREFIX}.processed_threads")
        end
      end
    end
  end
end
