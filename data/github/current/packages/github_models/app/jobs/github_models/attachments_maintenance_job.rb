# typed: strict
# frozen_string_literal: true

module GitHubModels
  class AttachmentsMaintenanceJob < GitHubModelsJob
    exempt_from_tenant_context_requirement

    queue_as :github_models_low_priority

    locked_by timeout: 1.minute, key: DEFAULT_LOCK_PROC
    schedule interval: 1.day, condition: -> { GitHub.models_enabled? }

    gate_with_feature_flag :github_models_attachments_maintenance_job

    sig { void }
    def perform
      GitHubModels::Attachment.where("created_at < ?", 1.week.ago).in_batches(of: 100) do |attachments|
        GitHub.logger.info("Deleting stale github models attachments", "gh.github_models.attachments.destroy_count": attachments.size)

        attachments.each do |attachment|
          GitHub.logger.info("Scheduling a deletion of the github models attachment", id: attachment.id)
          ::GitHubModels::AttachmentsCleanupJob.perform_later(attachment.id)
        end
      end
    end
  end
end
