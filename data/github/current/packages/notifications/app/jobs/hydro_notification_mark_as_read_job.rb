# typed: true
# frozen_string_literal: true

# Marks notification threads as read for a user. Locates threads by GlobalID, filters to
# unread threads, and marks each one as read via GitHub.newsies.web.mark_thread_read().
# Returns a status indicating the outcome (:success, :no_threads_provided, :no_user,
# :no_threads_found, :no_unread_threads).
#
# Enqueued by: Aqueduct Hydro Message Bridge from the notifications.v0.MarkAsRead Hydro
# message (published by NewsiesControllerHelper#async_mark_threads_as_read). When a user
# views an issue, PR, discussion, or other notifiable page, the controller publishes to
# Kafka, and the bridge routes it here. This decouples the mark-as-read DB write from the
# web request for latency reasons.
class HydroNotificationMarkAsReadJob < HydroMessageJob
  include HydroWaitForReplicasTrait

  wait_for_replicas ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Mysql1,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::NotificationsSummaries,
    ApplicationRecord::Repositories,
    ApplicationRecord::RepositoriesActionsChecks

  retry_on_dirty_exit

  queue_as :hydro_notification_mark_as_read

  set_callback :perform, :around, :with_semantic_logging

  def perform
    start = GitHub::Dogstats.monotonic_time
    status = :failure
    begin
      status = mark_as_read
    ensure
      GitHub.logger.info("Job finished", {
        "code.function" => "perform",
        "gh.user.id" => message[:user_id],
        "gh.job.threads" => message[:threads],
        "gh.job.status" => status.to_s,
      })
      GitHub.dogstats.distribution(
        "notifications.mark_as_read.perform.dist.time",
        GitHub::Dogstats.duration(start),
        tags: ["status:#{status}"]
      )
    end
  end

  private

  sig { returns(Symbol) }
  def mark_as_read
    return :no_threads_provided if message[:threads].empty?

    user = User.find_by(id: message[:user_id])
    return :no_user if user.blank?

    return :no_threads_found if threads.empty?

    unread = threads.select do |thread|
      response = GitHub.newsies.web.notification(user, thread.notifications_list, thread)

      response.success? && response.value&.unread?
    end

    return :no_unread_threads if unread.empty?

    with_primaries([ApplicationRecord::NotificationsEntries]) do
      unread.each do |thread|
        GitHub.newsies.web.mark_thread_read(user, thread)
      end
    end

    :success
  end

  sig { returns(T::Array[T.untyped]) }
  def threads
    @threads ||= message[:threads].filter_map { |gid| find_thread(gid) }
  end

  sig { params(gid: String).returns(T.untyped) }
  def find_thread(gid)
    GlobalID::Locator.locate gid # domain-isolation-query-violation:ignore:packages/issues (SELECT)
  rescue ActiveRecord::RecordNotFound, Newsies::Locator::NotFound => error
    GitHub.logger.info("Thread not found", {
      "code.function" => "find_thread",
      "gh.job.thread_gid" => gid,
      "exception.type" => error.class,
      "exception.message" => error.message,
    })
    nil
  rescue NameError => error
    GitHub.logger.info("Invalid GlobalID for Thread", {
      "code.function" => "find_thread",
      "gh.job.thread_gid" => gid,
      "exception.type" => error.class,
      "exception.message" => error.message,
    })
    nil
  end

  sig { params(block: T.proc.void).void }
  def with_semantic_logging(&block)
    name = self.class.name,
    context = logging_context.merge(
      "code.namespace" => name,
      "gh.job.name" => name,
    )
    GitHub.logger.with_named_tags(context, &block)
  end
end
