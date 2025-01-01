# typed: false
# frozen_string_literal: true

module Newsies
  # Marks a user's notifications as read, unread, or archived for a given query
  class MarkAllNotificationsFromQueryJob < ApplicationJob
    include ActiveJob::InitiallyEnqueuedAt
    include GitHub::Tracing

    queue_as :notifications
    retry_on_dirty_exit

    # Batch size to ensure we throttle queries appropriately
    BATCH_SIZE = 100
    LOCK_TIMEOUT = 1.hour

    # This rescue_from call ensures that if the retry_on calls below do not catch the error,
    # we clean up the JobStatus records to have the correct state of _error_.
    #
    # The retry_on calls below will enqueue a new job, but will not update the JobStatus.
    # This is by design, as we will be displaying this state to the end user. We do not want
    # the state to flap around if we have to retry jobs.
    #
    # NOTE: This rescue_from must come first as the global catch-all
    rescue_from StandardError do |error|
      Newsies::MarkAllNotificationsFromQueryJobStatus.status(self.arguments.first)&.error!
      NotificationsFailbot.report(error)
    end

    # Automatically retry when throttler errors are encountered.
    retry_on Freno::Throttler::Error, wait: :polynomially_longer, attempts: 10

    retry_on_recoverable_exceptions

    before_enqueue do |job|
      GitHub.tracer.in_span("create_query_job_status_before_enqueue", kind: :internal) do
        with_write do
          Newsies::MarkAllNotificationsFromQueryJobStatus.create(id: job.arguments.first, ttl: LOCK_TIMEOUT)
        end
      end
    end

    # user_id         - Integer user id
    # state           - State to mark notifications as (read, unread, archived)
    # filter_options  - Query options to refine scope for marking notifications,
    #                   See Newsies::Managers::Web.mark_all_from_query for supported options
    # offset_id       - Integer NotificationEntry id offset for working job in small batches
    # start_time      - The time that the job was initially kicked off. Used to track total duration accross all batches.
    def perform(user_id, state, filter_options = {}, offset_id = 0, start_time = initially_enqueued_at)
      job_status = Newsies::MarkAllNotificationsFromQueryJobStatus.status(user_id)
      return unless job_status

      with_write { job_status.started! }

      unless NotificationEntry::V2_STATE_TO_INTERNAL_STATE.keys.include?(state)
        raise ArgumentError, "invalid state #{state} provided"
      end

      unless user = User.find(user_id)
        raise ArgumentError, "user #{user_id} not found"
      end

      scope_options = filter_options.deep_dup

      scope_options[:lists] = active_record_objects_from_global_relay_ids(scope_options[:lists]) if scope_options[:lists]
      scope_options[:authors] = active_record_objects_from_global_relay_ids(scope_options[:authors]) if scope_options[:authors]
      scope_options[:owners] = active_record_objects_from_global_relay_ids(scope_options[:owners]) if scope_options[:owners]

      mark_at = scope_options[:before]
      scope = NotificationEntry.for_user(user).scope_from_options(scope_options)

      # apply job batching constraints
      scope = scope.where("id > ?", offset_id).limit(BATCH_SIZE).order(:id)

      GitHub.tracer.in_span("mark_as_scope_in_batch", kind: :internal, attributes: { "gh.user.id" => user.id, "gh.notifications.notification_entries.count" => scope.size }) do
        NotificationEntry.throttle_writes do
          ids = scope.pluck(:id)

          if !ids.empty?
            # construct a new simpler scope than the batched one, as passing the scope (formerly batch_scope)
            # to mark_scope_as directly results in very slow queries: https://github.com/github/github/issues/125284

            scope_to_update = NotificationEntry.where(id: ids)
            NotificationEntry.mark_scope_as(state, scope_to_update, mark_at)
          end

          if ids.size < BATCH_SIZE
            job_status.success!
            report_duration(start_time, state)
          else
            MarkAllNotificationsFromQueryJob.perform_later(user_id, state, filter_options, ids.max, start_time)
          end
        end
      end

      nil
    end

    def report_duration(start_time, state)
      duration = (Time.now - start_time) * 1_000
      GitHub.dogstats.distribution(
        "notifications.mark_all_notifications_from_query_job.dist.duration",
        duration,
        tags: ["state:#{state}"])
    end

    def active_record_objects_from_global_relay_ids(filter_values)
      filter_values.map do |value|
        type, id = ::Platform::Helpers::NodeIdentification.from_global_id(value)
        type.safe_constantize&.find_by(id: id)
      end
    end
  end
end
