# typed: true
# frozen_string_literal: true

module Newsies
  class CopilotDigestJobStatus
    JOB_KEY = "copilot-digest"

    # If the job hasn't completed within 2 minutes (queue wait + execution + polling),
    # the status expires and the client gets an error prompting a refresh.
    # The 1-minute dedup window is handled separately by the locked_by timeout in the job.
    DEFAULT_TTL = T.let(2.minutes, ActiveSupport::Duration)

    sig { params(actor_id: Integer, notification_ids: T::Array[String]).returns(String) }
    def self.job_id(actor_id, notification_ids)
      digest = Digest::SHA256.hexdigest(notification_ids.sort.join(":"))

      "#{prefix}-#{actor_id}-#{digest}"
    end

    sig { returns(String) }
    def self.prefix
      JOB_KEY
    end

    sig do
      params(
        actor_id: Integer,
        notification_ids: T::Array[String],
        context: T::Hash[Symbol, T.untyped]
      ).returns(Notifications::JobStatus)
    end
    def self.create(actor_id:, notification_ids:, context: {})
      Notifications::JobStatus.create(
        id: job_id(actor_id, notification_ids),
        ttl: DEFAULT_TTL,
        context: context.merge(actor_id: actor_id, notification_ids: notification_ids),
      )
    end

    sig { params(actor_id: Integer, notification_ids: T::Array[String]).returns(T.nilable(Notifications::JobStatus)) }
    def self.find(actor_id, notification_ids)
      Notifications::JobStatus.find(job_id(actor_id, notification_ids))
    end

    sig { params(actor_id: Integer, notification_ids: T::Array[String]).returns(Notifications::JobStatus) }
    def self.find!(actor_id, notification_ids)
      status = find(actor_id, notification_ids)
      raise JobStatus::NotFound, "job status id not found: #{job_id(actor_id, notification_ids)}" unless status

      status
    end

    sig { params(id: String).returns(T.nilable(Notifications::JobStatus)) }
    def self.lookup_by_id(id)
      Notifications::JobStatus.find(id)
    end

    sig { params(id: String).returns(Notifications::JobStatus) }
    def self.lookup_by_id!(id)
      status = lookup_by_id(id)
      raise JobStatus::NotFound, "job status id not found: #{id}" unless status

      status
    end
  end
end
