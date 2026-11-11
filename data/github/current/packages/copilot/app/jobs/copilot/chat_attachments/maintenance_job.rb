# typed: strict
# frozen_string_literal: true

module Copilot
  module ChatAttachments
    class MaintenanceJob < CopilotJob
      exempt_from_tenant_context_requirement

      queue_as :background_destroy
      retry_on_dirty_exit

      locked_by timeout: 12.hours, key: DEFAULT_LOCK_PROC
      schedule interval: 1.day, condition: -> { GitHub.copilot_enabled? }

      gate_with_feature_flag :copilot_chat_attachments_maintenance_job

      DOGSTATS_PREFIX = T.let("copilot.chat_attachments.maintenance_job", String)
      CE_CB_RETENTION = T.let(24.hours, ActiveSupport::Duration)
      DEFAULT_RETENTION = T.let(28.days, ActiveSupport::Duration)
      BATCH_SIZE = T.let(1_000, Integer)

      sig { void }
      def perform
        cleanup_default_stale_attachments

        return unless FeatureFlag.vexi.enabled?(:copilot_chat_attachments_ce_cb_short_retention, default: false)

        cleanup_ce_cb_stale_attachments
      end

      private

      sig { void }
      def cleanup_default_stale_attachments
        # Do not include Chat Attachments associated with Spaces Resources.
        chat_attachments_query = Copilot::ChatAttachment.where(created_at: ...DEFAULT_RETENTION.ago)
          .left_outer_joins(:copilot_space_resources)
          .where(custom_copilot_resources: { id: nil })
          .select(:created_at, :id)

        chat_attachments_query.in_batches(of: BATCH_SIZE, cursor: [:created_at, :id]) do |chat_attachments|
          GitHub.logger.info("Deleting stale copilot chat attachments", "gh.copilot.chat_attachments.destroy_count": chat_attachments.size)
          GitHub.dogstats.count("#{DOGSTATS_PREFIX}.destroy_count", chat_attachments.size)

          jobs = chat_attachments.map { |chat_attachment| ::Copilot::ChatAttachments::CleanupJob.new(chat_attachment.id) }
          ActiveJob.perform_all_later(jobs)
        end
      end

      sig { void }
      def cleanup_ce_cb_stale_attachments
        chat_attachments_query = Copilot::ChatAttachment.where(created_at: ...CE_CB_RETENTION.ago)
          .uploaded_by_potential_enterprise_or_business
          .left_outer_joins(:copilot_space_resources)
          .where(custom_copilot_resources: { id: nil })
          .preload(:uploader)
          .select(:created_at, :id, :uploader_id)

        chat_attachments_query.in_batches(of: BATCH_SIZE, cursor: [:created_at, :id]) do |chat_attachments|
          ce_cb_attachments = chat_attachments.select(&:uploaded_by_enterprise_or_business?)
          next if ce_cb_attachments.empty?

          GitHub.logger.info(
            "Deleting stale CE/CB copilot chat attachments",
            "gh.copilot.chat_attachments.ce_cb_destroy_count": ce_cb_attachments.size,
          )
          GitHub.dogstats.count("#{DOGSTATS_PREFIX}.ce_cb_destroy_count", ce_cb_attachments.size)

          jobs = ce_cb_attachments.map do |chat_attachment|
            age_hours = (Time.current - chat_attachment.created_at) / 1.hour
            GitHub.dogstats.histogram("#{DOGSTATS_PREFIX}.ce_cb_retention_hours", age_hours)
            ::Copilot::ChatAttachments::CleanupJob.new(chat_attachment.id)
          end
          ActiveJob.perform_all_later(jobs)
        end
      end
    end
  end
end
