# typed: true
# frozen_string_literal: true

class PurgeArchivedAssetsJob < TimedJob

  # While the AWS S3 batch delete API endpoint allows for up to 1000 objects,
  # our /internal/assets/archives API implementation and Alambic expect no
  # more than 100, so for now we constrain this setting to that maximum.
  MAX_BATCH_SIZE = 100

  # Each job runs for slightly more than 4 minutes, and there's a short
  # delay rescheduling the next job in each sequence, so over 58 jobs
  # the total run time is typically about 234 minutes.  Thus this should
  # result in a gap of about 5-6 minutes every 4 hours, if the number of
  # asset archives to be processed required even more jobs than defined
  # by this setting, which should generally not be necessary.
  MAX_JOBS_PER_SEQUENCE = 58

  # We constrain the maximum runtime of a single job to 4 minutes, so that
  # even accounting for AWS S3 delays in the final batch deletion request
  # we should stay below the 5-minute Kubernetes restart timeout period,
  # as advised in:
  # https://github.com/github/thehub/blob/b6822ec3def3c110a24c52b267aeb7be113c751d/docs/epd/engineering/products-and-services/dotcom/background-jobs/best-practices.md#limit-execution-time
  JOB_TIMEOUT = 4.minutes
  LOCK_TIMEOUT = JOB_TIMEOUT * 4

  queue_as :purge_archived_assets
  schedule interval: 1.hour, condition: -> { !GitHub.enterprise? }
  locked_by timeout: 1.hour, key: ActiveJob::LockingJob::DEFAULT_LOCK_PROC

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  exempt_from_tenant_context_requirement

  class MaximumJobCountExceeded < StandardError; end

  sig { override.returns(Float) }
  def timeout_sec
    JOB_TIMEOUT.to_f
  end

  sig do
    override
      .params(args: T.untyped, offset_id: Integer, kwargs: T.untyped)
      .returns(T.all(T::Enumerable[T.untyped], Object))
  end
  def fetch_batch(*args, offset_id:, **kwargs)
    oldest_time = Time.now - Asset::Archive.expiration_period

    # Per the guidance for limiting MySQL queries, we also constrain our query
    # batch size to 100, which happens to be the same as Alambic's maximum
    # batch size, but could be larger (or smaller).  For reference, see:
    # https://github.com/github/thehub/blob/b6822ec3def3c110a24c52b267aeb7be113c751d/docs/epd/engineering/dev-practicals/mysql/query-guidelines.md
    archives = ActiveRecord::Base.connected_to(role: :reading) do
      Asset::Archive.deletable_since(oldest_time, limit: MAX_BATCH_SIZE).to_a
    end

    # We don't want to pass individual asset archives to Alambic, as that
    # would be inefficient, since it can delete up to 100 objects at once.
    # Since this happens to be the same as the recommended maximum MySQL
    # query batch size, we just pass all the archives returned by our query
    # as an array element within a second array.  This element will be
    # treated as an individual item by the TimedJob, but will contain
    # up to 100 objects, all of which Alambic can process as a batch.
    archives.blank? ? [] : [archives]
  end

  sig { override.params(args: T.untyped, item: T.untyped, kwargs: T.untyped).void }
  def process_item(*args, item:, **kwargs)
    archives = T.cast(item, T::Array[Asset::Archive])

    oldest_archive_time = archives.first&.created_at
    GitHub.dogstats.gauge("archived_files.purge_offset", Time.now - oldest_archive_time) unless oldest_archive_time.nil?

    GitHub.dogstats.distribution_time("archived_files.purge_batch.dist.time") do
      Asset::Archive.throttle { Asset::Archive.purge(archives.map(&:id)) }
    end
  end

  sig { override.params(args: T.untyped, item: T.untyped, kwargs: T.untyped).returns(Integer) }
  def item_id(*args, item:, **kwargs)
    archives = T.cast(item, T::Array[Asset::Archive])
    archives.first&.id || 0
  end

  sig { override.params(args: T.untyped, kwargs: T.untyped).void }
  def finalize_sequence(*args, **kwargs)
    GitHub.dogstats.gauge("archived_files.purge_offset", Asset::Archive.expiration_period)
    GitHub.dogstats.gauge("archived_files.last_purge_job", kwargs[:num_in_sequence])
  end

  sig { params(num_in_sequence: Integer, kwargs: T.untyped).void }
  def perform(num_in_sequence: 1, **kwargs)
    state = :ok
    if num_in_sequence > MAX_JOBS_PER_SEQUENCE
      state = :error
      raise MaximumJobCountExceeded, "job enqueued with sequence number above maximum: #{num_in_sequence}, #{MAX_JOBS_PER_SEQUENCE}"
    end

    restraint = GitHub::Restraint.new
    restraint.lock!(T.must(self.class.name), 1, LOCK_TIMEOUT) do
      return super
    end
  rescue Asset::Archive::PurgeError => err
    state = :error
    Failbot.report(err)
    GitHub.dogstats.increment("archived_files.purge_error")
  rescue GitHub::Restraint::UnableToLock => err
    # report but do not retry
    Failbot.report(err)
    GitHub.dogstats.increment("archived_files.purge_job_lock")
  rescue MaximumJobCountExceeded => err
    # report but do not retry
    Failbot.report(err)
    GitHub.dogstats.increment("archived_files.purge_job_maximum")
  ensure
    GitHub.dogstats.increment("archived_files.purge_job", tags: ["state:#{state}"])
  end
end
