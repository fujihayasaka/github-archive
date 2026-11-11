# typed: true
# frozen_string_literal: true

# Generates a Copilot-powered digest summary of a user's notifications. Uses distributed
# locking (1-minute timeout) based on actor ID and sorted notification IDs to prevent
# duplicate digests. Checks the notifications_copilot_digest feature flag, retrieves job
# status (2-minute TTL), and calls the Copilot API create_notifications_digest with
# temperature 0.3. Tracks time-to-completion telemetry.
#
# Enqueued by: NotificationsV2Controller (app/controllers/notifications_v2_controller.rb)
# via the CopilotDigestJob.enqueue class method when a user requests a Copilot digest from
# the notifications UI.
class CopilotDigestJob < ApplicationJob
  queue_as :copilot_digest

  RETRYABLE_ERRORS = [
    Aqueduct::Worker::JobKilled,
    *Resiliency::Response::UnavailableExceptions,
  ].freeze

  LOCK_TIMEOUT = T.let(1.minute, ActiveSupport::Duration)

  locked_by timeout: LOCK_TIMEOUT, key: ->(job) {
    args = job.arguments[0] || {}
    notification_ids = args[:notification_ids]
    actor = args[:actor]

    # We lock the job based on actor id and notification ids to ensure that we don't have tons of jobs for the same actor and set of notifications.
    # This could result in out-of-date digest results since the underlying notifications could have changed between attempts to enqueue.
    # We also set a timeout of 1 minute to allow another job to be enqueued soon after, reducing staleness.
    [actor.id, notification_ids.sort.join(":")]
  }

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  sig { params(actor: User, notification_ids: T::Array[String]).void }
  def perform(actor:, notification_ids:)
    return unless FeatureFlag.vexi.enabled?(:notifications_copilot_digest, actor, default: false)

    # In case the queue is backed up and the job is attempted after the TTL of the job status, we should just bail gracefully since the client will have stopped polling and served a general error message.
    job_status = Newsies::CopilotDigestJobStatus.find(actor.id, notification_ids)
    unless job_status
      instrument_telemetry(actor, "copilot_digest_job.status_expired")
      return
    end

    track_job_status(job_status, actor: actor) do
      context = job_status.context || {}

      token = ::Copilot::DecryptedToken.from(context[:token] || "")

      copilot_api = Copilot::User.copilot_api(
        user: actor,
        integration_id: CopilotAPI::COPILOT_INNOVATION_INTEGRATION_ID,
        token: token
      )

      response = copilot_api.create_notifications_digest(
        notifications: context[:notification_summaries],
        model: context[:model],
        temperature: 0.3,
        allowed_ctas: Copilot::Notification::CTAS
      )

      ctx = job_status.context || {}
      ctx[:completion] = response
      job_status.context = ctx
      job_status.save
    end

    instrument_time_to_complete(job_status, actor)

    true
  end

  sig do
    params(
      actor: User,
      token: String,
      model: String,
      notification_ids: T::Array[String],
      notification_summaries: T::Array[T::Hash[Symbol, T.untyped]],
    ).returns(T.nilable(Notifications::JobStatus))
  end
  def self.enqueue(actor:, token:, model:, notification_ids:, notification_summaries:)
    return unless FeatureFlag.vexi.enabled?(:notifications_copilot_digest, actor, default: false)

    # Job status has a 2-minute TTL. If the job hasn't completed by then,
    # the status expires and the client sees an error prompting a refresh.
    # If one exists and is still running we return to continue polling for it
    existing = Newsies::CopilotDigestJobStatus.find(actor.id, notification_ids)
    return existing if existing && !existing.finished?

    context = {
      token: token,
      model: model,
      enqueued_at: Time.now.to_f,
      notification_summaries: notification_summaries,
    }

    job_status = Newsies::CopilotDigestJobStatus.create(
      actor_id: actor.id,
      notification_ids: notification_ids,
      context: context
    )

    perform_later(actor: actor, notification_ids: notification_ids)

    job_status
  end

  private

  sig { params(job_status: Notifications::JobStatus, actor: User, block: T.proc.void).void }
  def track_job_status(job_status, actor:, &block)
    job_status.started!
    yield
    job_status.success!
  rescue *RETRYABLE_ERRORS
    raise
  rescue => error
    # TODO: Add more robust error handling and categorization here to better understand failure modes and reduce noise.
    job_status_error!(job_status: job_status, actor: actor, error: error, message: "Something went wrong. Please try again.")
    instrument_telemetry(actor, "copilot_digest_job.failed", {
      "duration_ms" => duration_ms_since_enqueue(job_status),
      "error_type" => error.class.name.to_s,
      "error_message" => error.message.to_s,
    })
    raise
  end

  sig { params(actor: User, event: String, metadata: T::Hash[String, T.untyped]).void }
  def instrument_telemetry(actor, event, metadata = {})
    GlobalInstrumenter.instrument("copilot_notifications_inbox.telemetry", {
      user: actor,
      event: event,
      metadata: metadata,
    })
  end

  sig { params(job_status: Notifications::JobStatus, actor: User).void }
  def instrument_time_to_complete(job_status, actor)
    instrument_telemetry(actor, "copilot_digest_job.success", {
      "duration_ms" => duration_ms_since_enqueue(job_status),
    })
  end

  sig { params(job_status: Notifications::JobStatus).returns(T.nilable(Integer)) }
  def duration_ms_since_enqueue(job_status)
    context = job_status.context || {}
    enqueued_at = context[:enqueued_at]
    return unless enqueued_at

    ((Time.now.to_f - enqueued_at.to_f) * 1000).round
  end

  sig { params(job_status: Notifications::JobStatus, actor: User, error: Exception, message: T.nilable(String)).void }
  def job_status_error!(job_status:, actor:, error:, message: nil)
    message ||= error.message
    job_status.error!(message)

    GitHub.logger.error(
      "Failed to generate copilot digest",
      exception: error,
      "gh.actor.id": actor.id,
    )
  end
end
