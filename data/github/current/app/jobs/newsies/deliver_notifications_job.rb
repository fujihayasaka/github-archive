# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: false
# frozen_string_literal: true

module Newsies
  class DeliverNotificationsJob < ApplicationJob
    include SloHelper
    include GitHub::Tracing

    use_primaries ApplicationRecord::NotificationsEntries,
      ApplicationRecord::NotificationsSummaries,
      ApplicationRecord::Mysql2

    class JobInterrupted < StandardError; end

    # Utility class to log messages to debug notifications#1396 issue
    class Inspector
      attr_reader :enabled, :user_login
      alias_method :enabled?, :enabled

      def initialize(user)
        @user_login = user&.login
        @enabled = GitHub.flipper[:notifications_extra_logging_for_newsies_deliver_notifications_job].enabled?(user)
      end

      def log(msg = nil)
        return unless enabled?

        data = msg || yield
        GitHub.logger.info("Deliver notifications job", {
          "code.namespace" => "DeliverNotificationsJob",
          "gh.notifications.support_issue" => "notifications#1396",
          "gh.notifications.support_issue.message" => data[:message].to_s,
          "gh.notifications.support_issue.recipient" => user_login,
          "gh.notifications.support_issue.data" => data
        })
      end
    end

    # Timekeeper is a small utility class that helps keeping track of the time
    # spent in each stage of the delivery process so these times can be logged later
    # in a summary.
    #
    # This class wraps the main GitHub.dogstats.time method so whenever this is called
    # it also keeps track of that time to use it later.
    #
    # Calls to `#time` will be stacked so the final summary knows the order in which they
    # were called.
    class Timekeeper
      attr_reader :stack

      def initialize
        @stack = []
      end

      # This method is called internally when calling #clone or #dup
      def initialize_copy(original)
        @stack = original.stack.dup
      end

      def push(key, elapsed)
        @stack.push([key, elapsed])
      end

      def time(label, options = {}, &block)
        start = now
        GitHub.dogstats.time(label, options, &block)
      ensure
        # remove the "newsies" part of the label
        key = label.to_s.gsub("newsies.", "").gsub(".", "_")
        push(key, now - start)
      end

      def as_log(extra = {})
        payload = extra || {}
        stages = []
        @stack.each do |(key, elapsed)|
          payload[key] = elapsed ? elapsed : "unknown"
          stages.push key
        end

        payload[:stages] = stages.join("/")

        payload
      end

      private

      def now
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    end

    QUEUE_NAME = "deliver_notifications"

    DOG_STATS_PREFIX = "active_job.deliver_notifications_job".freeze

    queue_as do
      next "#{self.class::QUEUE_NAME}_low" if self.arguments.last.try(:fetch, :priority, nil) == :low
      self.class::QUEUE_NAME
    end

    DATABASE_UNAVAILABLE_EXCEPTIONS = [
      Freno::Throttler::Error,
      *Resiliency::Response::UnavailableExceptions
    ]

    retry_on(
      *DATABASE_UNAVAILABLE_EXCEPTIONS,
      JobInterrupted,
      wait: :polynomially_longer,
      attempts: 20,
    )

    retry_on_dirty_exit

    around_perform :use_mysql1_replica

    before_enqueue do |job|
      klass = job.arguments[0]
      GitHub.dogstats.increment("#{DOG_STATS_PREFIX}.before_enqueue", tags: [
        "subject_type:#{klass}"
      ])
    end

    after_perform do |job|
      klass = job.arguments[0]
      GitHub.dogstats.increment("#{DOG_STATS_PREFIX}.after_perform", tags: [
        "subject_type:#{klass}"
      ])
    end

    attr_reader :delivery_priority

    # A subset of the reasons returned by `reason_to_stop_delivery` that describe a situation in
    # which we should both skip notification delivery and subsequently delete all of user's
    # newsies data for a given list.
    REASONS_TO_PURGE_NEWSIES_DATA = [:newsies_disabled, :list_unreadable]

    # Number of subscribers we want to notify in single throttle block
    BATCH_SIZE = 10

    resolve_tenant_context do |klass, id|
      object = klass.constantize.find_by_id(id)
      Notifications::TenantContext.resolve_tenant(object&.notifications_list)
    end

    # Delivers a notification.
    #
    # klass          - String ActiveRecord class name.
    # id             - Integer ID of the record.
    # recipient_ids  - (Optional) Array of User IDs to which we should deliver the notifications. If
    #                  omitted, the default of `nil` will cause us to deliver notifications to all
    #                  users who are subscribed to the given content.
    # reason         - (Optional) String specifying the reason for the message. If omitted, the
    #                  default of `nil` will cause us to deliver notifications with the "mentioned"
    #                  reason.
    # options        - Hash<String, Object> specifying job options
    #                  - :event_time  - Integer/Float timestamp of the time the event that triggered
    #                    the notification was created (e.g. comment.created_at)
    #                  - :enqueued_at - UTC Integer/Float timestamp of the time the job was queued
    #                    (e.g. Time.now.utc.to_f)
    #                  - priority - Symbol (e.g. :high, :low) used to specify the queue to process the job on.
    #                  - :unsaved_tracked_deliveries - Hash<String, Array> deprecated.
    #                  - :is_update - Indication of whether or not the notification is for an update event.
    #                  - :delivered_subscribers - Array of User IDs that have already been delivered to in this job.
    def perform(klass, id, recipient_ids = nil, reason = nil, event_time:, enqueued_at: nil, priority: :high, unsaved_tracked_deliveries: nil, is_update: false, delivered_subscribers: nil)
      @delivered_subscribers = delivered_subscribers
      GitHub.tracer.in_span("job.deliver_notifications", kind: :internal, attributes: { "gh.notifications.delivery.reason" => reason.to_s }) do
        init_timekeeper(event_time: event_time, enqueued_at: enqueued_at)
        @delivery_priority = priority

        return unless object = klass.constantize.find_by_id(id)
        return unless list = object.notifications_list
        return unless thread = object.notifications_thread

        comment = object.is_a?(PullRequest) ? object.issue : object

        return unless comment_deliverable?(list, thread, comment)

        delivery = timekeeper.time("newsies.delivery.build") do
          summary = GitHub.tracer.in_span("NotificationSummary.fetch_and_update!", kind: :internal) do
            NotificationSummary.fetch_and_update!(list, thread, comment)
          end
          Delivery.new(summary, comment)
        end

        return unless delivery.list && delivery.thread

        @datadog_tags = []

        explicit_subscribers = recipient_ids&.map do |recipient_id|
          Newsies::Subscriber.new(recipient_id, true, false, reason || "mention")
        end

        timekeeper.time("newsies.delivery.send") do
          GitHub.tracer.in_span("deliver_to_subscribers", kind: :internal, attributes: { "gh.notifications.delivery.reason" => reason.to_s }) do
            deliver_to_subscribers(
              delivery,
              explicit_subscribers: explicit_subscribers,
              enqueued_at: enqueued_at,
              event_time: event_time,
              is_update: is_update,
            )
          end
        end
      rescue Exception
        save_delivered_state
        raise
      ensure
        GitHub.logger.info("full notifications job processed", {
          "code.namespace" => "DeliverNotificationsJob",
          "code.function" => "perform",
          "gh.notifications.timekeeper.delay_time" => timekeeper.as_log[:delay_time],
          "gh.notifications.timekeeper.queued_time" => timekeeper.as_log[:queued_time],
          "gh.notifications.timekeeper.stages" => timekeeper.as_log[:stages]
        })
      end
    end

    private

    # Checks if the list/thread/comment should be delivered as notifications at all
    # or if we should abort delivery early
    def comment_deliverable?(list, thread, comment)
      return false unless list.present? && thread.present? && comment.present?
      return false if comment.notifications_author&.spammy?
      true
    end

    def deliver_to_subscribers(delivery, event_time:, explicit_subscribers: nil, enqueued_at: nil, is_update: false)
      hygiene = DeliveryHygiene.new(delivery)

      delivered = delivered_to_author = 0
      subscribers = GitHub.tracer.in_span("subscribers_with_preloaded_settings", kind: :internal) do
        GitHub.newsies.subscribers_with_preloaded_settings(
          delivery.list,
          delivery.thread,
          explicit_subscribers,
        ).value!
      end

      handler_list.each do |handler_key|
        GitHub.dogstats.count("newsies.delivery.counter", subscribers.size, tags: ["type:potential_deliveries", "handler:#{handler_key}"])
      end

      author = (delivery.comment || delivery.thread).try(:notifications_author)

      add_subscriber_set_size_datadog_tag(subscribers.length)

      # Filter out subscribers that have already been delivered to.
      if @delivered_subscribers
        subscribers.delete_if { |subscriber| @delivered_subscribers.include?(subscriber.user_id) }
      else
        @delivered_subscribers = []
      end

      # We batch the subscribers in groups of 10 and perform deliveries
      # following those batches
      subscribers.each_slice(BATCH_SIZE) do |batched_subscribers|
        # Race conditions here are possible and common. Sometimes the state of
        # the subject that triggered this delivery changes while on flight
        # (things are removed or marked as spam)
        #
        # That's why we check here, on every slice to ensure that we always
        # prepare a cleanup for spammy deliveries or removed threads.
        #
        # For unhealthy deliveries (for example, the thread as been removed) we
        # then halt the whole process instead of continuing with deliveries and
        # immediately enqueue a cleanup.
        #
        # For spam we proceed with deliveries and enqueue a cleanup at the end
        # so that, in case the spam detection failed with a false possitive, we
        # can roll it back.
        #
        # More about this here: https://github.com/github/notifications/issues/462
        if hygiene.halt?
          GitHub.dogstats.count("newsies.delivery.halts", subscribers.length, tags: @datadog_tags)

          break
        end

        # check authorization for the batch of subscribers
        authorized_subscribers = GitHub.tracer.in_span("authorize_subscribers", kind: :internal) do
          ActiveRecord::Base.connected_to(role: :reading) do
            Newsies::PolicyManager.authorize_subscribers(delivery.list, delivery.thread, batched_subscribers)
          end
        end

        filtered_subscribers = batched_subscribers.size - authorized_subscribers.size
        if filtered_subscribers > 0
          handler_list.each do |handler_key|
            GitHub.dogstats.count("newsies.delivery.counter", filtered_subscribers, tags: ["filter:authorize_subscribers", "type:filter", "handler:#{handler_key}"])
          end
        end

        NotificationEntry.throttle do
          authorized_subscribers.each do |subscriber|
            if deliver_email_to_author?(subscriber, author, explicit_subscribers)
              GitHub.tracer.in_span("deliver_email_to_author", kind: :internal,
                                    attributes: {
                                      "gh.notifications.delivery.own_activity" => "true",
                                      "gh.user.id" => subscriber.user_id,
                                    }) do
                deliver_to_single_subscriber(
                  delivery,
                  subscriber,
                  subscriber_wants_email_for_own_activity: true,
                  enqueued_at: enqueued_at,
                  event_time: event_time,
                  is_update: is_update,
                  author: author,
                )
                delivered += 1
                delivered_to_author += 1
                @delivered_subscribers << subscriber.user_id
              end
            elsif deliver_regularly?(delivery, subscriber, author, explicit_subscribers)
              GitHub.tracer.in_span("deliver_to_single_subscriber", kind: :internal,
                                    attributes: {
                                      "gh.notifications.delivery.regular" => "true",
                                      "gh.user.id" => subscriber.user_id,
                                    }) do
                deliver_to_single_subscriber(
                  delivery,
                  subscriber,
                  enqueued_at: enqueued_at,
                  event_time: event_time,
                  is_update: is_update,
                  author: author,
                )
                delivered += 1
                @delivered_subscribers << subscriber.user_id
              end
            end

            GitHub.tracer.in_span("graceful_shutdown", kind: :internal) do
              graceful_shutdown!(hygiene)
            end
          end
        end # throttle
      end # subscribers.each_slice(BATCH_SIZE)

      # After we exit the subscriber loop, we check whether a cleanup is needed
      # or not and prepare it. If it is not needed this call is a noop
      hygiene.cleanup

      GitHub.dogstats.count("newsies.delivery.delivered", delivered)
      GitHub.dogstats.count("newsies.delivery.delivered_to_author", delivered_to_author)
      if delivered_to_author == 0
        handler_list.each do |handler_key|
          GitHub.dogstats.increment("newsies.delivery.counter", tags: ["filter:author_skipped", "type:filter", "handler:#{handler_key}"])
        end
      end
    end

    # Returns true if all of the following are true...
    #   - the list of subscribers set explicitly _does not_ include the author
    #   - the given subscriber is also the author
    #   - the subscriber/author has subscribed to their own updates to be
    #   emailed
    #
    # Returns truthy or falsey
    def deliver_email_to_author?(subscriber, author, explicit_subscribers)
      explicit_subscribers ||= []

      author &&
        explicit_subscribers.map(&:user_id).exclude?(author.id) &&
        subscriber_is_author?(subscriber, author) &&
        subscribed_to_own_updates?(subscriber.settings)
    end

    def subscriber_is_author?(subscriber, author)
      subscriber.user && subscriber.user == author
    end

    def subscribed_to_own_updates?(settings)
      settings &&
        settings.participating_email? &&
        settings.notify_own_via_email?
    end

    # Checks whether the given subscriber should be notified.
    #
    # Returns truthy or falsey
    def deliver_regularly?(delivery, subscriber, author, explicit_subscribers)
      return false unless subscribed_to_event?(subscriber, event_name_from_delivery(delivery))

      is_explicitly_set_user = explicit_subscribers && explicit_subscribers.include?(subscriber)
      is_author = subscriber_is_author?(subscriber, author)
      (
        (!is_author || is_explicitly_set_user) &&
        deliver_from_author?(delivery.list, author, subscriber.user)
      )
    end

    # Checks whether the subscriber is subscribed to the specific event we are notifying
    #           about.
    def subscribed_to_event?(subscriber, event_name)
      # if subscriber is not subscribed to specific events, then they are subscribed by default
      return true if subscriber.events.empty?

      # if event name is undefined, then it definitely doesn't match the user's preferences
      return false if event_name.nil?

      # the subscriber is only subscribed if their defined events match the event_name
      subscriber.events.include?(event_name)
    end

    # Determine the event name from the delivery object
    #
    # Currently this only considers IssueEvent events
    def event_name_from_delivery(delivery)
      case delivery.comment
      when IssueEventNotification
        delivery.comment.issue_event.event
      end
    end

    # FIXME: (@franciscoj 25/08/2023) this has 9 parameters and the first thing
    # it does is to build a n object with 5 of them. This object could be
    # passed instead of built inside?
    def deliver_to_single_subscriber(delivery, subscriber, event_time:, subscriber_wants_email_for_own_activity: false, enqueued_at: nil, is_update: false, author: nil)
      options = DeliveryOptions.new(
        delivery: delivery,
        subscriber: subscriber,
        subscriber_wants_email_for_own_activity: subscriber_wants_email_for_own_activity,
      )

      inspector = Inspector.new(subscriber.user)

      handlers = options.handlers

      excluded_handlers = handler_list - handlers
      excluded_handlers.each do |handler_key|
        GitHub.dogstats.increment("newsies.delivery.counter", tags: ["filter:handler_filter", "type:filter", "handler:#{handler_key}"])
      end

      inspector.log do
        {
          message: "preparing handlers",
          handlers: handlers,
        }
      end

      GitHub.tracer.in_span("record_ghost_web_notification", kind: :internal) do
        record_ghost_web_notification(options, event_time)
      end

      handlers.each do |handler_key|
        GitHub.tracer.in_span("handlers", kind: :internal,
                              attributes: {
                                "gh.notifications.delivery.handler" => handler_key,
                              }) do
          handler_key = handler_key.to_s
          handler = GitHub.newsies.handlers.detect { |h| h.handler_key.to_s == handler_key }

          if !handler.present?
            GitHub.dogstats.increment("newsies.delivery.counter", tags: ["filter:handler_missing", "type:filter", "handler:#{handler_key}"])
            next
          end

          inspector.log do
            {
              message: "going to send notification",
              handler: handler_key,
              reason: options.reason,
            }
          end

          # Dup the main Timekeeper to keep track only of the time spent in this single notification
          subkeeper = timekeeper.dup
          delivered = subkeeper.time("newsies.deliver.time", tags: ["handler:#{handler_key}", "thread_type:#{delivery.thread_type}"]) do
            GitHub.tracer.in_span("handler.deliver", kind: :internal,
                                  attributes: {
                                    "gh.notifications.delivery.handler" => handler_key,
                                    "gh.notifications.thread.type" => delivery.thread_type,
                                  }) do
              # Some comments (like IssueEventNotification and RepositoryAdvisoryEvent) need to know who they are being delivered to
              # as delivery is happening.
              if delivery.comment.respond_to?(:register_recipient)
                GitHub.tracer.in_span("delivery.comment.register_recipient", kind: :internal,
                                  attributes: {
                                    "gh.notifications.user.settings.id" => subscriber.settings.id,
                                  }) do
                  delivery.comment.register_recipient subscriber.settings.id
                end
              end

              delivered = handler.deliver(
                delivery,
                subscriber.settings,
                event_time: event_time,
                reason: options.reason,
                root_job_enqueued_at: enqueued_at,
                priority: delivery_priority,
                extra_tags: @datadog_tags + [
                  "priority:#{delivery_priority}",
                  "reason:#{subscriber.reason}",
                  "participating:#{Newsies::Reasons::Participating.include?(subscriber.reason.to_sym)}",
                  "source:newsies",
                ],
                inspector: inspector,
                is_update: is_update,
                author: author,
              )

              inspector.log do
                {
                  message: "notification delivery attempted",
                  handler: handler_key,
                  reason: options.reason,
                  delivered: !!delivered,
                }
              end

              delivered
            end
          end

          next unless delivered

          GitHub.logger.info("single notification sent", {
            "code.namespace" => "DeliverNotificationsJob",
            "code.function" => "deliver_to_single_subscriber",
            "gh.notifications.handler" => handler_key
          })
        end
      end
    end

    # Record a metric to log subscribers that don't currently have web notifications
    # enabled.
    #
    # This will allow us to estimate the impact if web notifications were
    # enabled for everybody, or if we started to write web notifications for everybody.
    #
    # options - Newsies::DeliveryOptions
    # event_time - Time
    def record_ghost_web_notification(options, event_time)
      return if options.subscriber_wants_email_for_own_activity
      return if options.handlers.include?("web")

      # Estimate whether this would be an inserted notification or an update
      # If the comment type is the same as the thread type, it's probably a new thread
      is_new_thread = options.delivery.thread_type == options.delivery.comment_type

      GitHub.dogstats.increment("newsies.web_disabled_for_subscriber", tags: [
        "reason:#{options.subscriber.reason}",
        "email_enabled:#{options.handlers.include?("email")}",
        "is_new_thread:#{is_new_thread}",
      ])
    end

    # Checks to see if the user can receive a notification by the author or
    # repository owner.
    #
    # list   - A Repository.
    # author - The User that created the notification.
    # user   - The User due to receive a notification.
    #
    # Returns true if the user can receive the notification, or false.
    def deliver_from_author?(list, author, user)
      return if !user || !user.newsies_enabled?
      users = [list.owner, author].compact
      ActiveRecord::Base.connected_to(role: :reading) do
        !user.avoid?(*users)
      end
    end

    # Mapping of (inclusive) upper bound of the number of subscribers to a tag name
    SUBSCRIBER_SET_SIZE_BUCKETS = [
      [10,              "subscriber_set_size:small"],
      [100,             "subscriber_set_size:medium"],
      [1000,            "subscriber_set_size:large"],
      [10000,           "subscriber_set_size:x-large"],
      [Float::INFINITY, "subscriber_set_size:xx-large"],
    ]

    # Find a tag for the metric with a bucketed number of subscribers. We cannot create a tag
    # for every unique number of subscribers, so this buckets the values so we can estimate
    # distributions.
    def add_subscriber_set_size_datadog_tag(subscriber_set_size)
      @datadog_tags.push(
        SUBSCRIBER_SET_SIZE_BUCKETS
          .find { |(upper_bound_ms, _)| subscriber_set_size <= upper_bound_ms }
          .second,
      )
    end

    # If the aqueduct worker running this job has signaled shutdown, we save state, clean up,
    # and raise an exception to exit gracefully and cause the job to be retried.
    def graceful_shutdown!(hygiene)
      return unless $aqueduct_worker&.shutdown?

      hygiene.cleanup

      GitHub.dogstats.increment("newsies.delivery.interrupted", tags: @datadog_tags)
      raise JobInterrupted
    end

    def save_delivered_state
      self.arguments.last[:delivered_subscribers] = @delivered_subscribers
      GitHub.dogstats.count("newsies.delivery.saved_delivered_subscribers", @delivered_subscribers&.size || 0, tags: @datadog_tags)
    end

    # When initializing the Timekeeper, set the following stage times
    #
    # * delay_time: time since the event was triggered until it was picked by this job
    # * queued_time: time spent in the queue
    def init_timekeeper(event_time: nil, enqueued_at: nil)
      @timekeeper = Timekeeper.new
      now = Time.now.to_f

      # Time since the event was triggered and this job started to run
      delay_time = event_time ? now - event_time.to_f : nil
      @timekeeper.push(:delay_time, delay_time)

      # Time in the queue
      queued_time = enqueued_at ? now - enqueued_at.to_f : nil
      @timekeeper.push(:queued_time, queued_time)
    end

    def timekeeper
      @timekeeper ||= Timekeeper.new
    end

    def handler_list
      @handler_list ||= GitHub.newsies.handlers.map(&:handler_key).map(&:to_s)
    end
  end
end
