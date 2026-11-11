# typed: true
# frozen_string_literal: true

# This job identifies and deletes orphaned Azure Blob Storage containers for Spark workbenches
# that no longer have corresponding records in the database.
#
# ## Purpose: Safety Net for Orphaned Containers
#
# This job complements the immediate deletion feature (spark_snapshot_cleanup) by serving as a
# cleanup safety net for:
# - Pre-existing orphaned containers (from before immediate deletion)
# - Containers orphaned due to failed immediate deletions (network errors, API failures)
# - Edge cases where immediate deletion didn't run (race conditions, exceptions)
#
# The immediate deletion feature handles 99%+ of cases; this job catches the remainder.
#
# ## Job Triggering
#
# This job is automatically scheduled to run daily at ~2am UTC. The job checks the feature flag
# `spark_background_blob_detection` at runtime and will skip execution if the flag is disabled.
#
# 1. Automatic scheduling (recommended for production):
#    - Runs daily at ~2am UTC via config/timers.proxima.rb
#    - Checks feature flag `spark_background_blob_detection` before executing
#    - Processes up to 1,000 containers per run (configurable via limit parameter)
#    - Controlled by TWO feature flags for safe rollout:
#      * `spark_background_blob_detection`: Enables the job (REQUIRED - must be on for job to run)
#      * `spark_background_blob_deletion`: Enables actual deletion (OPTIONAL - upgrades to deletion mode)
#        - When DISABLED (default): Job runs in detection/dry-run mode (logs only, no deletion)
#        - When ENABLED: Job performs actual deletion of orphaned containers
#
# 2. Manual trigger (for testing or ad-hoc cleanup):
#    Workbench::DeleteOrphanedBlobContainersJob.perform_later(limit: 1000, dry_run: true)
#
# 3. External scheduler (CI/CD, Kubernetes CronJob, etc.)
#
# Note: The job uses a Redis mutex to prevent concurrent executions, so multiple
# triggers will safely queue but not run simultaneously. Feature flags are checked
# at execution time, not schedule time.
#
# ## Rollout Strategy (Two-Phase Approach)
#
# Phase 1 - Detection/Observation (Safe Mode):
#   - Enable `spark_background_blob_detection` flag (job starts running)
#   - Keep `spark_background_blob_deletion` DISABLED (default: false)
#   - Job runs in dry-run mode: identifies and logs orphaned containers
#   - Monitor logs and metrics to validate detection logic
#   - Verify no false positives (containers incorrectly identified as orphans)
#
# Phase 2 - Active Deletion:
#   - Keep `spark_background_blob_detection` enabled (job continues running)
#   - Enable `spark_background_blob_deletion` flag
#   - Job upgrades to deletion mode: actually deletes orphaned containers
#   - Can quickly disable deletion flag if issues are detected (returns to detection mode)
#
# IMPORTANT: The `spark_background_blob_detection` flag MUST be enabled for the job to run.
# If only `spark_background_blob_deletion` is enabled, the job will NOT run at all.
#
# ## Configuration Parameters
#
# - `limit`: The maximum number of containers to process across all batches (default: 1_000).
# - `batch_size`: The number of containers to process in each batch (default: 100).
# - `dry_run`: A flag to indicate whether the job should run in dry-run mode, skipping actual deletion.
#   When not explicitly provided, defaults based on the `spark_background_blob_deletion` feature flag:
#   - If deletion flag is DISABLED: dry_run = true (detection mode)
#   - If deletion flag is ENABLED: dry_run = false (deletion mode)
# - `offset_item_id`: A marker string for Azure pagination (default: "").
# - `progress`: The current progress of the job, representing the number of containers processed so far (default: 0).
#
# ## Scaling Expectations
#
# Initial runs may process many pre-existing orphans (could take 20-30 minutes).
# After cleanup stabilizes, each run should find very few orphans (<10) as immediate deletion
# handles the majority of cases. The orphan rate should decrease over time, not increase.
#
module Workbench
  class DeleteOrphanedBlobContainersJob < BatchedJob

    queue_as :workbench

    # Feature flag to enable this job (detection/observation mode)
    # This flag MUST be enabled for the job to run at all
    FEATURE_FLAG = "spark_background_blob_detection"

    # Feature flag to enable actual deletion (upgrades from detection to deletion mode)
    # When DISABLED (default): Job runs in dry-run/detection mode (logs only, no deletion)
    # When ENABLED: Job performs actual deletion of orphaned containers
    # Note: FEATURE_FLAG must also be enabled for this flag to have any effect
    DELETION_FLAG = "spark_background_blob_deletion"

    # Schedule: Run hourly (job checks feature flag internally before executing)
    schedule interval: 1.hour, condition: -> { !GitHub.enterprise? }

    retry_on_dirty_exit

    # Default size of a single batch to be processed
    BATCH_SIZE = 100

    # Maximum number of containers to process in a single run; keep under Azure list limits
    DEFAULT_LIMIT = 1_000

    # Azure's List Containers API rejects max_results > 5_000
    AZURE_MAX_RESULTS = 5_000

    # The key used for the Redis mutex to prevent concurrent execution of this job.
    MUTEX_KEY = "workbench:delete_orphaned_blob_containers"

    # Prefix for metrics related to this job.
    METRICS_PREFIX = "workbench.jobs.delete_orphaned_blob_containers"

    sig { returns(T.nilable(String)) }
    attr_accessor :next_marker

    sig { params(args: T.untyped, kwargs: T.untyped).void }
    def initialize(*args, **kwargs)
      super
      @next_marker = T.let(nil, T.nilable(String))
    end

    # Find the next batch of containers to check for orphans
    #
    # offset_item_id - marker string for Azure pagination
    # progress - the current progress of the job
    # limit - maximum number of containers to process
    # **kwargs - additional parameters
    #
    # Returns an array of container name strings
    #
    sig do
      override.params(
        args: T.untyped,
        timestamp: Time,
        offset_item_id: T.any(String, Integer),
        progress: Integer,
        limit: Integer,
        kwargs: T.untyped
      ).returns(T::Array[String])
    end
    def next_batch(*args, timestamp: Time.now.utc, offset_item_id: "", progress: 0, limit: DEFAULT_LIMIT, **kwargs)
      unless job_enabled?
        GitHub.dogstats.increment("#{METRICS_PREFIX}.skipped", tags: ["cause:flag_disabled"])
        GitHub.logger.info("Feature flag is disabled", job: self.class.name, flag: FEATURE_FLAG)
        return []
      end

      unless mutex.try_lock
        GitHub.dogstats.increment("#{METRICS_PREFIX}.skipped", tags: ["cause:job_lock"])
        GitHub.logger.info("Cannot obtain the job lock", job: self.class.name)
        return []
      end

      return [] if progress >= limit

      # List containers from Azure Blob Storage
      blob_client = get_blob_client

      # Use marker (offset_item_id) for pagination
      # Convert offset_item_id to string, handle both String and Integer types
      marker_value = offset_item_id.to_s.presence

      max_results = [BATCH_SIZE, limit - progress].min
      max_results = max_results.clamp(1, AZURE_MAX_RESULTS)

      options = {
        max_results: max_results
      }
      options[:marker] = marker_value if marker_value

      begin
        GitHub.logger.info(
          "Listing containers from blob storage",
          job: self.class.name,
          progress: progress,
          limit: limit,
          max_results: max_results,
          marker_present: marker_value.present?,
          marker_length: marker_value&.length
        )
        result = blob_client.list_containers(options)

        # Extract container names and store continuation token
        container_names = result.map(&:name)
        @next_marker = result.continuation_token

        GitHub.logger.info(
          "Listed containers from blob storage",
          job: self.class.name,
          batch_size: container_names.size,
          has_more: @next_marker.present?,
          progress: progress
        )

        container_names
      rescue Azure::Core::Http::HTTPError => e
        GitHub.logger.error(
          "Failed to list containers",
          job: self.class.name,
          error: e.message,
          status_code: e.status_code,
          progress: progress,
          limit: limit,
          max_results: max_results,
          marker_present: marker_value.present?,
          marker_length: marker_value&.length
        )
        GitHub.dogstats.increment("#{METRICS_PREFIX}.list_containers_error", tags: ["status:#{e.status_code}"])
        []
      end
    end

    # Process a batch of containers - check for orphans and delete them
    #
    # container_names - array of container name strings
    # dry_run - if true, only log what would be deleted. If not provided, checks feature flag.
    # **kwargs - additional parameters
    #
    sig do
      override.params(
        container_names: T::Array[String],
        args: T.untyped,
        dry_run: T.nilable(T::Boolean),
        kwargs: T.untyped
      ).void
    end
    def process_batch(container_names, *args, dry_run: nil, **kwargs)
      return if container_names.empty?

      # Determine dry-run mode: use explicit parameter if provided, otherwise check feature flag
      effective_dry_run = dry_run.nil? ? dry_run_enabled? : dry_run

      # Convert container names (UUID strings) to binary format for database lookup
      binary_uuids = container_names.map { |name| T.unsafe(Spark::Workbench).binary_uuid(name) }

      # Batch lookup all workbenches at once (avoids N+1 queries)
      existing_workbenches = T.unsafe(Spark::Workbench).where(uuid: binary_uuids)

      # Get existing UUID strings using the model's uuid_string method
      existing_uuid_strings = existing_workbenches.map(&:uuid_string)

      # Find orphaned containers using set subtraction
      orphaned_containers = container_names - existing_uuid_strings

      GitHub.logger.info(
        "Found orphaned containers",
        job: self.class.name,
        total_checked: container_names.size,
        orphaned_count: orphaned_containers.size,
        dry_run: effective_dry_run
      )

      GitHub.dogstats.count("#{METRICS_PREFIX}.containers_checked", container_names.size)
      GitHub.dogstats.count("#{METRICS_PREFIX}.orphaned_containers_found", orphaned_containers.size)

      # Delete orphaned containers
      if effective_dry_run
        GitHub.logger.info(
          "DRY RUN: Would delete orphaned containers",
          job: self.class.name,
          containers: orphaned_containers
        )
        GitHub.dogstats.count("#{METRICS_PREFIX}.dry_run_deletions", orphaned_containers.size)
      else
        orphaned_containers.each do |container_name|
          delete_container(container_name)
        end
      end
    end

    # Determine the offset for the next batch using Azure's continuation token
    sig do
      override.params(
        container_names: T::Array[String],
        args: T.untyped,
        kwargs: T.untyped
      ).returns(T.any(String, Integer))
    end
    def next_batch_offset_item_id(container_names, *args, **kwargs)
      # Use the continuation token from Azure, or empty string if none
      @next_marker || ""
    end

    # Check if there are more batches to process
    sig do
      override.params(
        container_names: T::Array[String],
        limit: Integer,
        progress: Integer,
        kwargs: T.untyped
      ).returns(T::Boolean)
    end
    def has_next_batch?(container_names, limit: DEFAULT_LIMIT, progress: 0, **kwargs)
      # Continue if we have a next_marker AND we haven't reached the limit
      T.cast(@next_marker.present? && (progress + container_names.size) < limit, T::Boolean)
    end

    # Cleanup method that runs after job completes
    sig do
      override.params(
        finished_successfully: T::Boolean,
        kwargs: T.untyped
      ).void
    end
    def ensure_perform(finished_successfully:, **kwargs)
      mutex.unlock if mutex.locked?

      GitHub.logger.info(
        "Job execution complete",
        job: self.class.name,
        finished_successfully: finished_successfully
      )
    end

    private

    # Check if the job is enabled via feature flag
    sig { returns(T::Boolean) }
    def job_enabled?
      FeatureFlag.vexi.enabled?(FEATURE_FLAG, ::User.staff_user, default: false)
    end

    # Check if dry-run mode should be enabled
    # Dry-run is enabled when the deletion flag is DISABLED (inverted logic)
    # Returns true if actual deletion should be skipped (detection/observation mode)
    # Can be overridden by explicit dry_run parameter in job invocation
    sig { returns(T::Boolean) }
    def dry_run_enabled?
      # Dry-run is enabled when deletion flag is DISABLED
      !FeatureFlag.vexi.enabled?(DELETION_FLAG, ::User.staff_user, default: false)
    end

    # Get the Azure Blob Service client
    sig { returns(T.untyped) }
    def get_blob_client
      Workbench::SnapshotBlobs.get_blob_client
    end

    # Delete a single container
    sig { params(container_name: String).void }
    def delete_container(container_name)
      start_time = GitHub::Dogstats.monotonic_time

      GitHub.logger.info(
        "Deleting orphaned container",
        job: self.class.name,
        container_name: container_name
      )

      T.unsafe(Workbench::SnapshotBlobs).delete_container(container_name)

      GitHub.dogstats.distribution("#{METRICS_PREFIX}.container_deletion_duration_ms", GitHub::Dogstats.duration(start_time))
      GitHub.dogstats.increment("#{METRICS_PREFIX}.container_deleted", tags: ["success:true"])
    rescue Azure::Core::Http::HTTPError => e
      GitHub.dogstats.distribution("#{METRICS_PREFIX}.container_deletion_duration_ms", GitHub::Dogstats.duration(start_time), tags: ["error:true"])

      # 404 means already deleted - not an error
      if e.status_code == 404
        GitHub.logger.info("Container already deleted", job: self.class.name, container_name: container_name)
        GitHub.dogstats.increment("#{METRICS_PREFIX}.container_deleted", tags: ["success:true", "reason:already_deleted"])
      else
        GitHub.logger.error("Failed to delete container", job: self.class.name, container_name: container_name, error: e.message, status_code: e.status_code)
        GitHub.dogstats.increment("#{METRICS_PREFIX}.container_deleted", tags: ["success:false", "status:#{e.status_code}"])
      end
      # Don't raise - continue processing other containers
    rescue StandardError => e
      GitHub.dogstats.distribution("#{METRICS_PREFIX}.container_deletion_duration_ms", GitHub::Dogstats.duration(start_time), tags: ["error:true"])

      GitHub.logger.error("Unexpected error deleting container", job: self.class.name, container_name: container_name, error: e.message)
      GitHub.dogstats.increment("#{METRICS_PREFIX}.container_deleted", tags: ["success:false", "error:unexpected"])
      # Don't raise - continue processing other containers
    end

    # Get or create a Redis mutex for this job
    #
    # Mutex prevents concurrent execution of this job to avoid duplicate work.
    # Timeout is set to 1 hour to allow the job to complete even during:
    # - Initial runs with many pre-existing orphans (~20-30 minutes expected)
    # - Slower-than-expected Azure API responses
    # - Network latency or rate limiting
    #
    # This timeout is appropriate for background maintenance jobs that:
    # - Run asynchronously (don't block user requests)
    # - Only hold a Redis key (not database locks)
    # - Self-complete or expire naturally
    sig { returns(GitHub::Redis::Mutex) }
    def mutex
      @mutex ||= T.let(
        GitHub::Redis::Mutex.new(MUTEX_KEY, timeout: 1.hour.to_i),
        T.nilable(GitHub::Redis::Mutex)
      )
    end
  end
end
