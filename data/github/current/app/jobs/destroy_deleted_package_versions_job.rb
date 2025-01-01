# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class DestroyDeletedPackageVersionsJob < ApplicationJob
  queue_as :background_destroy
  schedule interval: 1.hour, condition: -> { !GitHub.enterprise? }
  retry_on_dirty_exit

  MAX_THROTTLE_RETRIES = 5

  # This job is operating at the stamp level and it's not tenant context aware
  exempt_from_tenant_context_requirement

  # How long deleted package versions are retained for restore. After this
  # period they are destroyed and unrecoverable.
  def expiration_period
    3.months
  end

  def perform
    # safeguard feature flag to exit early if necessary
    return if GitHub.flipper[:packages_disable_destroy_delete_package_versions_job].enabled?

    read_batch_size = 1000
    expire_time ||= Time.now - expiration_period
    ttl = 600.seconds # 10 minute delete loop
    end_at = ttl.from_now
    start = Time.current

    destroyed_versions = 0

    begin
      stop_reason = catch(:stop) do
        loop do
          package_versions_to_delete = get_batch_to_delete(expire_time, read_batch_size)
          if package_versions_to_delete.empty?
            throw :stop, :empty_batch
          end

          ActiveRecord::Base.connected_to(role: :writing) do
            package_versions_to_delete.each do |version|
              # When calling .destroy there are a number of active record callbacks that are triggered which is why package versions
              # are deleted one by one instead of using bulk sql with something like delete_all. Below is a list of objects that also gets deleted and callbacks
              Registry::PackageVersion.throttle_with_retry(max_retry_count: MAX_THROTTLE_RETRIES) do
                version.destroy
              end

              destroyed_versions += 1

              if Time.current >= end_at
                throw :stop, :ttl
              end
            end
          end
        end
      end
    # If an exception is raised, we set the stop reason to exception and re-raise the exception.
    # The ensure block will still run and log the stop reason and other metrics.
    rescue
      stop_reason = :exception
      raise
    ensure
      GitHub.logger.info(
        "info.message" => "DestroyDeletedPackageVersionsJob finished.",
        "gh.destroy_deleted_package_versions_job.stop_reason" => stop_reason,
        "gh.destroy_deleted_package_versions_job.read_batch_size" => read_batch_size,
        "gh.destroy_deleted_package_versions_job.ttl" => ttl,
        "gh.destroy_deleted_package_versions_job.spend_duration" => Time.current - start,
        "gh.destroy_deleted_package_versions_job.destroyed_versions" => destroyed_versions,
      )

      GitHub.dogstats.count("destroy_deleted_package_versions_job.finished", 1, tags: [
        "reason:#{stop_reason}",
        "read_batch_size:#{read_batch_size}",
        "ttl:#{ttl}"])

      GitHub.dogstats.count("destroy_deleted_package_versions_job.destroyed_versions", destroyed_versions)
    end
  end

  private

  def get_batch_to_delete(expire_time, batch_size)
    ActiveRecord::Base.connected_to(role: :writing) do
      # fetch batch of records from primary in-case of replication lag and don't sort by ID since it is not covered by the index
      Registry::PackageVersion
        .from("package_versions FORCE INDEX(index_package_versions_on_package_deleted_at)")
        .where("package_versions.deleted_at < ?", expire_time)
        .limit(batch_size)
        .annotate("/*DestroyDeletedPackageVersionsJob.get_batch_to_delete*/")
    end
  end
end
