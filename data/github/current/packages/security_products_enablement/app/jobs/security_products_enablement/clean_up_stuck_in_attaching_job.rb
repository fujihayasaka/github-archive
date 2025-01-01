# typed: strict
# frozen_string_literal: true

module SecurityProductsEnablement
  # CleanUpStuckInAttachingJob processes repository security configurations that have been
  # stuck in the "attaching" state for more than 8 hours. It performs the following actions:
  #
  # 1. For configurations where the repository has been deleted: deletes the configuration
  # 2. For configurations where the repository still exists: marks the configuration as "failed"
  #
  # The job uses batch repository existence checking via Repositories::Public.load_repositories
  # to avoid N+1 queries when processing large numbers of configurations.
  class CleanUpStuckInAttachingJob < ApplicationJob
    retry_on_dirty_exit
    retry_on_recoverable_exceptions

    queue_as :clean_up_stuck_in_attaching

    schedule interval: 1.hour

    BATCH_SIZE = 100
    MAX_RECORDS_PER_RUN = 100000
    CUTOFF_HOURS = 8

    sig { void }
    def perform
      cutoff_time = CUTOFF_HOURS.hours.ago
      failure_reason = "Attachment process exceeded timeout (#{CUTOFF_HOURS} hours)"

      stuck_configs = RepositorySecurityConfiguration
        .where(state: :attaching)
        .where("repository_security_configurations.updated_at < ?", cutoff_time)
        .includes(:user)  # Preload the organization (user relationship) to avoid N+1 queries
        .limit(MAX_RECORDS_PER_RUN)

      updated_count = 0
      deleted_count = 0
      failed_count = 0
      total_found = 0

      stuck_configs.find_in_batches(batch_size: BATCH_SIZE) do |batch|
        total_found += batch.size
        # Get repository IDs for this batch and check existence
        repository_ids = batch.map(&:repository_id)
        active_repository_ids = Set.new(Repositories::Public.load_repositories(repository_ids).pluck(:id))

        # Process each configuration in the batch
        batch.each do |config|
          begin
            organization = config.user
            next unless organization # Skip if organization is nil

            stuck_duration_hours = ((Time.current - config.updated_at) / 1.hour.to_f).to_i

            # Check if the repository still exists
            if active_repository_ids.include?(config.repository_id)
              # Repository exists, mark configuration as failed
              RepositorySecurityConfiguration.throttle_writes_with_retry do
                config.update!(
                  state: :failed,
                  failure_reason: failure_reason
                )
              end
              updated_count += 1

              GitHub.logger.info(
                "Marked repository security configuration as failed due to timeout",
                "gh.security_products_enablement.repository_security_configuration_id": config.id,
                "gh.repo.id": config.repository_id,
                "gh.org.id": organization.id,
                "gh.org.login": organization.display_login,
                "gh.security_products_enablement.stuck_duration_hours": stuck_duration_hours,
                "gh.security_products_enablement.previous_state": "attaching"
              )

              GitHub.dogstats.increment("security_products_enablement.cleanup_job.stuck_config_marked_failed")
            else
              # Repository has been deleted, so delete the configuration
              RepositorySecurityConfiguration.throttle_writes_with_retry do
                config.destroy!
              end
              deleted_count += 1

              GitHub.logger.info(
                "Deleted repository security configuration for deleted repository",
                "gh.security_products_enablement.repository_security_configuration_id": config.id,
                "gh.repo.id": config.repository_id,
                "gh.org.id": organization.id,
                "gh.org.login": organization.display_login,
                "gh.security_products_enablement.stuck_duration_hours": stuck_duration_hours,
                "gh.security_products_enablement.previous_state": "attaching",
                "gh.security_products_enablement.action": "deleted_for_missing_repository"
              )

              GitHub.dogstats.increment("security_products_enablement.cleanup_job.config_deleted_for_missing_repo")
            end
          rescue ActiveRecord::RecordNotFound
            # Record was deleted between query and update - this is fine, just continue
            failed_count += 1
          rescue StandardError => e # rubocop:todo Lint/GenericRescue
            failed_count += 1
            GitHub.dogstats.increment("security_products_enablement.cleanup_job.update_failed")
            GitHub.logger.error(
              "Failed to update stuck repository security configuration",
              "gh.security_products_enablement.repository_security_configuration_id": config.id,
              "gh.repo.id": config.repository_id,
              "gh.org.id": organization&.id,
              "error.message": e.message,
              "error.class": e.class.name
            )
          end
        end
      end

      GitHub.logger.info(
        "Completed cleanup of stuck repository security configurations",
        "gh.security_products_enablement.updated_count": updated_count,
        "gh.security_products_enablement.deleted_count": deleted_count,
        "gh.security_products_enablement.failed_count": failed_count,
        "gh.security_products_enablement.total_found": total_found
      )

      GitHub.dogstats.gauge("security_products_enablement.cleanup_job.configs_processed", updated_count + deleted_count + failed_count)
      GitHub.dogstats.gauge("security_products_enablement.cleanup_job.configs_updated", updated_count)
      GitHub.dogstats.gauge("security_products_enablement.cleanup_job.configs_deleted", deleted_count)
      GitHub.dogstats.gauge("security_products_enablement.cleanup_job.configs_failed", failed_count)
    end
  end
end
