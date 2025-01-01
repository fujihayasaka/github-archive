# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class TransitionMediaBlobsJob < ApplicationJob
  RETRYABLE_ERRORS = [
    Media::Blob::CopyError,
    Net::OpenTimeout,
    Net::ReadTimeout,
    NoMethodError,
  ].freeze

  queue_as :lfs
  locked_by timeout: 10.minutes, key: ->(job) {
    job.arguments[0]["id"].to_i
  }
  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  retry_on(*RETRYABLE_ERRORS)

  def perform(options)
    finished = false
    id = options["id"]
    Media::Transition.throttle do
      return unless transition = Media::Transition.find_by(id: id.to_i)
      with_write { transition.perform }
    end
    finished = true
  rescue ActiveRecord::RecordInvalid => err
    # In all likelihood, we have a blob that lacks an asset and this
    # operation is never going to complete, so we avoid rescheduling the
    # current job to be retried by ActiveJob.
    # Note that a new job will be enqueued for this operation the next
    # time QueueMediaTransitionJobsJob runs, however.
    GitHub.logger.error(
      "Not retrying TransitionMediaBlobsJob", {
        exception: err,
        "gh.media.transition.id": options["id"],
        "exception.record.class.name": err.record.class.name,
        "exception.record.id": err.record&.id,
      })
  rescue GitHub::DataQualityError, Media::Transition::MissingRepositoryNetworkError, Media::Transition::MissingRepositoryNetworkOwnerError => err
    # We either have a missing repository network or one which is missing
    # a root repository or owner, hence this operation may never complete,
    # so we avoid rescheduling the current job to be retried by ActiveJob.
    # Note that a new job will be enqueued for this operation the next
    # time QueueMediaTransitionJobsJob runs, however.
    # In the case of a Media::Transition::MissingRepositoryNetworkError
    # or Media::Transition::MissingRepositoryNetworkOwnerError,
    # after five such job attempts, the sixth job will delete the transition
    # record permanently.
    GitHub.logger.error(
      "Not retrying TransitionMediaBlobsJob", {
        exception: err,
        "gh.media.transition.id": options["id"],
      })
  rescue Media::Blob::CopyError, NoMethodError, Net::OpenTimeout, Net::ReadTimeout => err
    if err.is_a?(Media::Blob::CopyError)
      Failbot.report_user_error(err)
    end
    GitHub.logger.error(
      "Retrying TransitionMediaBlobsJob", {
        exception: err,
        "gh.media.transition.id": options["id"],
      })
    raise
  ensure
    state = finished ? :ok : :error
    GitHub.dogstats.increment("lfs.transition_job", tags: ["state:#{state}"])
  end
end
