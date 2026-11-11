# typed: strict
# frozen_string_literal: true

module Copilot
  module MemoryAdminExports
    class BlobCleanupJob < CopilotJob
      exempt_from_tenant_context_requirement

      queue_as :copilot_memory_admin_exports_blob_cleanup
      retry_on_dirty_exit
      locked_by timeout: 30.minutes, key: DEFAULT_LOCK_PROC
      schedule interval: 1.day, condition: -> { GitHub.copilot_for_business_enabled? }

      sig { void }
      def perform
        result = Copilot::MemoryAdminExport.cleanup_expired_blobs
        GitHub.logger.info(
          "Copilot memory admin export blob cleanup completed",
          "gh.copilot_memory_admin_export.blob_cleanup.listed" => result.fetch(:listed),
          "gh.copilot_memory_admin_export.blob_cleanup.eligible" => result.fetch(:eligible),
          "gh.copilot_memory_admin_export.blob_cleanup.deleted" => result.fetch(:deleted),
          "gh.copilot_memory_admin_export.blob_cleanup.skipped" => result.fetch(:skipped),
          "gh.copilot_memory_admin_export.blob_cleanup.pages" => result.fetch(:pages),
        )
        GitHub.dogstats.increment("copilot.memory_admin_export.blob_cleanup", tags: ["result:success"])
        GitHub.dogstats.gauge("copilot.memory_admin_export.blob_cleanup.deleted", result.fetch(:deleted))
        GitHub.dogstats.gauge("copilot.memory_admin_export.blob_cleanup.skipped", result.fetch(:skipped))
      rescue Copilot::MemoryAdminExport::Storage::Error => error
        payload = {
          "gh.copilot_memory_admin_export.blob_cleanup.result" => "error",
          "gh.error.class" => error.class.name,
        }
        Failbot.report(error, payload)
        GitHub.logger.warn("Copilot memory admin export blob cleanup failed", payload)
        GitHub.dogstats.increment("copilot.memory_admin_export.blob_cleanup", tags: ["result:error"])
        raise
      end
    end
  end
end
