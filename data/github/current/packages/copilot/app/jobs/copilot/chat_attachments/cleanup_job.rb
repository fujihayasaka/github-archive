# typed: strict
# frozen_string_literal: true

module Copilot
  module ChatAttachments
    class CleanupJob < CopilotJob
      TENANT_RESOLUTION_FLAG = :copilot_chat_attachments_cleanup_resolve_tenant
      DOGSTATS_PREFIX = "copilot.chat_attachments.cleanup_job"

      resolve_tenant_context do |attachment_id|
        attachment = ::Copilot::ChatAttachment.select(:id, :uploader_id).find_by(id: attachment_id)
        if attachment.nil?
          GitHub.dogstats.increment("#{DOGSTATS_PREFIX}.tenant_resolution_failed", tags: ["reason:attachment_missing"])
          next nil
        end

        uploader = ::User.find_by(id: attachment.uploader_id)
        if uploader.nil?
          GitHub.dogstats.increment("#{DOGSTATS_PREFIX}.tenant_resolution_failed", tags: ["reason:uploader_missing"])
          next nil
        end

        business = uploader.enterprise_managed_business
        if business.nil?
          GitHub.dogstats.increment("#{DOGSTATS_PREFIX}.tenant_resolution_failed", tags: ["reason:uploader_not_emu"])
          next nil
        end

        business
      end

      queue_as :background_destroy
      retry_on_dirty_exit

      locked_by timeout: 1.minute, key: ->(job) do
        attachment_id = T.let(job.arguments.first, Integer)
        attachment_id.to_s
      end

      retry_on Storage::Uploadable::DeletionError, Faraday::Error,
        attempts: 3, wait: :polynomially_longer

      sig { params(attachment_id: Integer).void }
      def perform(attachment_id)
        GitHub.logger.with_named_tags("gh.copilot.chat_attachment.id": attachment_id) do
          if GitHub.multi_tenant_enterprise? && GitHub::CurrentTenant.get.nil?
            if FeatureFlag.vexi.enabled?(TENANT_RESOLUTION_FLAG, default: true)
              reap_orphan_attachment(attachment_id)
            else
              GitHub.logger.warn("Skipping copilot chat attachment cleanup; no tenant resolved")
              GitHub.dogstats.increment("#{DOGSTATS_PREFIX}.tenant_not_resolved")
            end
            return
          end

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
            GitHub.dogstats.increment("#{DOGSTATS_PREFIX}.skipped_space_resource")
            return
          end

          begin
            with_write { attachment.destroy! }
          rescue => e
            if e.is_a?(Storage::Uploadable::DeletionError) && e.status == 404
              with_write { attachment.delete }
              GitHub.logger.info(
                "Deleted orphaned chat attachment row; blob already gone in storage",
                age_days: ((Time.current - attachment.created_at) / 1.day).round(1),
                state: attachment.state,
              )
              GitHub.dogstats.increment("#{DOGSTATS_PREFIX}.deleted_orphaned_row")
              return
            end

            GitHub.logger.error(
              "Failed to destroy copilot chat attachment",
              exception: e,
              "error.class": e.class.to_s,
              "error.cause": e.cause&.class&.to_s,
            )
            tags = ["error:#{e.class.to_s.underscore}"]
            tags << "status:#{e.status}" if e.is_a?(Storage::Uploadable::DeletionError)
            GitHub.dogstats.increment("#{DOGSTATS_PREFIX}.destroy_attempt_failed", tags: tags)
            raise
          end

          GitHub.logger.info("Destroyed copilot chat attachment")
          GitHub.dogstats.increment("#{DOGSTATS_PREFIX}.deleted_attachments")
        end
      end

      private

      # Hard-deletes only the DB row; without tenant context we can't construct the
      # storage URL, so blob TTL handles GC.
      sig { params(attachment_id: Integer).void }
      def reap_orphan_attachment(attachment_id)
        GitHub::CurrentTenant.unscope do
          row = ::Copilot::ChatAttachment.where(id: attachment_id).pluck(:uploader_id, :created_at).first
          if row.nil?
            GitHub.logger.warn("Skipping orphan reaper; copilot chat attachment row no longer exists")
            GitHub.dogstats.increment("#{DOGSTATS_PREFIX}.orphan_skipped", tags: ["reason:attachment_missing"])
            return
          end
          uploader_id, created_at = row

          uploader = ::User.find_by(id: uploader_id)
          reason =
            if uploader.nil?
              "uploader_missing"
            elsif uploader.enterprise_managed_business.nil?
              "uploader_not_emu"
            else
              "tenant_now_resolvable"
            end

          if reason == "tenant_now_resolvable"
            GitHub.logger.warn("Skipping orphan reaper; tenant became resolvable between resolver and perform")
            GitHub.dogstats.increment("#{DOGSTATS_PREFIX}.orphan_skipped", tags: ["reason:tenant_now_resolvable"])
            return
          end

          # Atomically delete only if no CopilotSpaceResource references it.
          deleted_count = with_write do
            ::Copilot::ChatAttachment
              .where(id: attachment_id)
              .where("NOT EXISTS (SELECT 1 FROM custom_copilot_resources WHERE custom_copilot_resources.copilot_chat_attachment_id = copilot_chat_attachments.id)")
              .delete_all
          end

          if deleted_count.zero?
            GitHub.logger.warn("Skipping orphan reaper; copilot chat attachment is associated with a copilot space resource")
            GitHub.dogstats.increment("#{DOGSTATS_PREFIX}.orphan_skipped", tags: ["reason:space_resource"])
            return
          end

          GitHub.logger.warn(
            "Reaped orphaned copilot chat attachment without tenant context; storage blob may leak",
            reason: reason,
            age_days: ((Time.current - created_at) / 1.day).round(1),
          )
          GitHub.dogstats.increment("#{DOGSTATS_PREFIX}.orphan_reaped", tags: ["reason:#{reason}"])
        end
      end
    end
  end
end
