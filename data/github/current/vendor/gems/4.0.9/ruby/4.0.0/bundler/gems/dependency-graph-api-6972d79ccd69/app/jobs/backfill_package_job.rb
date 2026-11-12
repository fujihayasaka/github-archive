# frozen_string_literal: true

# When we ingest an npm package we also perform a one-off import of that
# package to backfill any missing versions.
#
# After npm replication changes discussed here https://github.com/orgs/community/discussions/152515
# we realized we were missing versions of packages. This was highlighted by the Shai
# Hulud attacks, as some of the affected packages were not in our database.
class BackfillPackageJob < RetryJob
  queue_as :package_backfill

  def perform(package_manager, package_name)
    cache_key = "backfill:#{package_manager}:#{CGI.escape(package_name)}"

    # Skip if already processed within the cache window
    return if Rails.cache.read(cache_key)

    OneOffImporters.run!(package_manager, package_name: package_name)
    
    # Mark as processed to prevent duplicate backfills
    Rails.cache.write(cache_key, true, expires_in: 1.hour)
  rescue StandardError => e
    Rails.logger.error("Failed to backfill #{package_manager} package #{package_name}: #{e}")
    Failbot.report(
      e,
      "gh.aqueduct.queue.name" => queue_name,
      "gh.aqueduct.job.name" => "backfill_package_job"
    )
    # Don't cache on error - allows retry on subsequent call
  end
end
