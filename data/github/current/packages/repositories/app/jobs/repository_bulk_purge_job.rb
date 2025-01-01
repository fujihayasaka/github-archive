# typed: true
# frozen_string_literal: true

# This job bulk purges soft-deleted repositories from the production Repositories table
class RepositoryBulkPurgeJob < ApplicationJob
  queue_as :repository_bulk_purge
  retry_on_dirty_exit
  retry_on GitHub::Gitbackups::ClientError
  retry_on Faraday::TimeoutError

  INTERVAL = 2.minutes
  # Only one of these jobs should run at any given time.
  locked_by timeout: INTERVAL, key: ActiveJob::LockingJob::DEFAULT_LOCK_PROC

  schedule interval: INTERVAL

  exempt_from_tenant_context_requirement

  BATCH_SIZE = 500
  FAILED_CREATION_BATCH_SIZE = 5
  MINIMUM_AGE_TO_PURGE = 90.days
  ACCEPTABLE_DELAY_SECONDS = 1.0
  CLUSTER_NAME = :repositories
  KV_KEY = "repository_bulk_purge_last_batch_size"
  INACTIVE_DAYS = (1..5).freeze
  INACTIVE_HOURS = (12..22).freeze

  def self.expiration_period
    MINIMUM_AGE_TO_PURGE
  end

  def high_replication_lag?
    # Default to a 1 second threshold
    # The FF percentage, if present, map to thresholds of 0.1 - 10 seconds.
    percentage = GitHub.flipper[:repository_bulk_purge_delay_threshold].percentage_of_time_value
    threshold = percentage > 0 ? 0.1 * percentage : ACCEPTABLE_DELAY_SECONDS
    delay = Freno.client.replication_delay(store_name: CLUSTER_NAME)
    delay > threshold
  rescue Freno::Error
    true
  end

  def during_peak_hours?
    utc_now = Time.now.utc
    GitHub.flipper[:skip_repo_purge_during_peak].enabled? && INACTIVE_DAYS.include?(utc_now.wday) && INACTIVE_HOURS.include?(utc_now.hour)
  end

  def compute_batch_size
    max_batch_size = BATCH_SIZE
    if GitHub.flipper[:repository_bulk_purge_custom_batch_size].percentage_of_time_value > 0
      max_batch_size = GitHub.flipper[:repository_bulk_purge_custom_batch_size].percentage_of_time_value.to_i * 10
    end

    # during times of high replication lag, drop batch size to 0
    # the replication lag indicator is spiky though, so don't resume with large batch sizes right away
    # when replication lag goes away, slowly ramp up the batch size again
    batch_size = Repositories::Kv.store.get(KV_KEY).value { 0 }.to_i
    batch_size = during_peak_hours? || high_replication_lag? ? batch_size - 100 : batch_size + 10
    batch_size = [batch_size, 0].max
    batch_size = [batch_size, max_batch_size].min

    begin
      with_write { Repositories::Kv.store.set(KV_KEY, batch_size.to_s) }
    rescue GitHub::KV::UnavailableError
      # noop
    end
    batch_size
  end

  def perform(batch_size = 0)
    purged = 0
    if batch_size <= 0
      batch_size = compute_batch_size
    end

    # shifting 12 hours back to switch the deletes from highest period of deletes to the lowest
    end_date = (Time.now - RepositoryBulkPurgeJob.expiration_period) - 12.hours

    GitHub.dogstats.gauge("repository_bulk_purge.purgeable", Repository.deleted_before(end_date).count)

    # no-op if replication lag is too high
    repos = find_repos_to_purge(batch_size, end_date)

    GitHub.dogstats.gauge("repository_bulk_purge.batch", repos.size)

    repos.each do |repo|
      begin
        orchestration = with_write { RepositoryOrchestration.purge(repo) }
        with_write { orchestration.execute }
      rescue => e # rubocop:disable Lint/GenericRescue
        GitHub.logger.error(
          :exception => e,
          "code.namespace" => self.class.name,
          "code.function" => __method__,
          "gh.repo.id" => repo.id
        )
      end

      if orchestration&.failed?
        GitHub.logger.error(
          orchestration.error_message,
          "code.namespace" => self.class.name,
          "code.function" => __method__,
          "gh.repo.id" => repo.id
        )
      end
    end

    GitHub.logger.info(
      "Performing repository bulk purge job",
      "code.namespace" => self.class.name,
      "code.function" => __method__,
      "gh.repo.purge.end_date" => end_date,
      "gh.repo.purge.count" => repos&.size,
      "gh.repo.purge.batch_size" => batch_size
    )

    repos&.size
  end

  # Will return approximately batch_size repos to destroy.
  # May return more because they'll all getting deleted anyway and it's inefficient to prune them and re-calculate them next time.
  # May return less if there are fewer available in the age range.
  def find_repos_to_purge(batch_size, end_date)
    return [] if batch_size <= 0

    legal_hold_users = LegalHold.distinct.pluck(:user_id).to_set
    hold = T.let [], T::Array[Repository]
    purge = T.let [], T::Array[Repository]
    sample_rate = GitHub.flipper[:repo_purge_batch_size_sample_rate].percentage_of_time_value
    multiplier = sample_rate > 0 ? (100 / sample_rate).to_i : 0

    if multiplier > 0
      batch = Repositories::Public.find_old_deleted_repos(multiplier * batch_size, end_date)
      batch = batch.sample(batch.size / multiplier)
    else
      batch = Repositories::Public.find_old_deleted_repos(batch_size, end_date)
    end

    if batch.size < batch_size
      failed_creation_batch_size = FAILED_CREATION_BATCH_SIZE
      if GitHub.flipper[:repo_purge_failed_creation_batch_size].percentage_of_time_value.to_i > 0
        failed_creation_batch_size = GitHub.flipper[:repo_purge_failed_creation_batch_size].percentage_of_time_value.to_i * 5
      end

      failed_creations = Repositories::Public.failed_creations([failed_creation_batch_size, batch_size - batch.size].min)
      GitHub.dogstats.gauge("repository_bulk_purge.failed_creations", failed_creations.size)
      batch += failed_creations
    end

    # separate the repos we cannot purge from the repos we can
    hold, purge = batch.partition { |repo| legal_hold_users.include?(repo.owner_id) }

    # touch the legally-held repos so they don't show up in this query for a while
    with_write do
      hold.each do |r|
        r.touch
      end
    end

    purge
  end
end
