# typed: false
# frozen_string_literal: true

# This job purges soft-deleted gists from the production Gists table
class GistPurgeJob < ApplicationJob
  queue_as :archive_restore
  retry_on_dirty_exit
  retry_on GitHub::Gitbackups::ClientError
  retry_on Faraday::TimeoutError

  INTERVAL = 10.minutes
  locked_by timeout: INTERVAL, key: ActiveJob::LockingJob::DEFAULT_LOCK_PROC
  schedule interval: INTERVAL

  exempt_from_tenant_context_requirement

  BATCH_SIZE = 1000
  MINIMUM_AGE_TO_PURGE = 90.days

  def self.expiration_period
    MINIMUM_AGE_TO_PURGE
  end

  def self.enabled?
    !GitHub.multi_tenant_enterprise?
  end

  def perform(batch_size = 0)
    if batch_size <= 0
      batch_size = BATCH_SIZE
    end

    end_date = (Time.now - GistPurgeJob.expiration_period)

    count = purge_gists(batch_size, end_date)
    GitHub.dogstats.gauge("gist_purge.purge_count", count)

    GitHub.logger.info(
      "Gist purge job completed",
      "code.namespace" => "GistPurgeJob",
      "code.function" => "perform",
      "gh.gist.purge.end_date" => end_date,
      "gh.gist.purge.count" => count,
      "gh.gist.purge.batch_size" => batch_size
    )
  end

  def purge_gists(batch_size, end_date)
    return 0 if batch_size <= 0

    legal_hold_users = LegalHold.distinct.pluck(:user_id).to_set
    batch = []

    ActiveRecord::Base.connected_to(role: :reading) do
      batch = Gist.deleted_before(end_date, batch_size)
    end

    # separate the gists we cannot purge from the gists we can
    hold, purge = batch.partition { |gist| legal_hold_users.include?(gist.user_id) }

    failed_creations = Gist.where(delete_flag: true)
                            .where(updated_at: 1.day.ago..1.hour.ago)
                            .where("created_at = updated_at")
                            .where(pushed_count: 0)
                            .limit([batch_size - purge.count, 0].max)
    purge += failed_creations
    GitHub.logger.info(
      "Purging failed gist creations",
      "code.namespace" => "GistPurgeJob",
      "code.function" => "perform",
      "gh.gist.purge.end_date" => end_date,
      "gh.gist.purge.batch_size" => batch_size,
      "gh.gist.purge.failed_creations" => failed_creations.limit(100).map { |g| g.id }.join(", ")
    )

    ActiveRecord::Base.connected_to(role: :writing) do
      # touch the legally-held gists so they don't show up in this query for a while
      hold.each(&:touch)

      purge.each(&:purge)
    end

    batch.length
  end
end
