# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

module Newsies
  # This job will copy the existing thread subscriptions for one thread to another
  #
  # Notes:
  # - Should not be called directly with `perform` but with `copy_thread_subscribers`. This will ensure that we find the subscriptions synchronously
  #   and before they are potentially deleted by the original thread getting deleted.
  # - This job will not check that all users can still read the thread. This will get caught by a future notification delivery, and these superfluous
  #   subscriptions removed
  class CopyThreadSubscribersJob < ApplicationJob

    include GitHub::Tracing
    trace_method(
      :sync_thread_to_notifyd,
      span_annotator: -> (instance, span, _context, _result) do
        span.add_attributes(instance.trace_attributes)
      end
    )

    trace_method(
      :handle_errors,
      span_attribute_extractor: -> (instance, *_args, **kwargs) do
        instance.trace_attributes.merge({ "gh.notifications.notifyd_method" => kwargs[:method] })
      end
    )

    queue_as :notifications

    retry_on_recoverable_exceptions
    retry_on_dirty_exit

    attr_reader :trace_attributes

    # batch size for iterating the users in the job to ensure we throttle queries appropriately
    BATCH_SIZE = 100

    FIELDS_FOR_COPY = [:user_id, :reason, :ignored]

    sig { params(old_thread: ActiveRecord::Base, new_thread: T.nilable(ActiveRecord::Base)).void }
    def self.copy_thread_subscribers(old_thread, new_thread)
      # Eject if the new_thread (e.g. issue) has been deleted before this job has had
      # a chance to run. See # https://github.com/github/data-partitioning/issues/708 for example.
      return if new_thread.nil?

      old_newsies_list = Newsies::List.to_object(T.unsafe(old_thread).notifications_list)
      old_newsies_thread = Newsies::Thread.to_object(T.unsafe(old_thread).notifications_thread,
        list: old_newsies_list)

      new_newsies_list = Newsies::List.to_object(T.unsafe(new_thread).notifications_list)
      new_newsies_thread = Newsies::Thread.to_object(T.unsafe(new_thread).notifications_thread,
        list: new_newsies_list)

      subscribers_info = ThreadSubscription.for_thread(old_newsies_thread)
                                           .pluck(*T.unsafe(FIELDS_FOR_COPY))
                                           .map { |row| FIELDS_FOR_COPY.zip(row).to_h }

      subscribers_info.each_slice(BATCH_SIZE) do |subscribers_info_batch|
        perform_later(
          new_newsies_list.type,
          new_newsies_list.id,
          new_newsies_thread.type,
          new_newsies_thread.id,
          subscribers_info_batch
        )
      end
    end

    SubscriberInfo = T.type_alias do
      {
        user_id: T.any(Integer, String),
        reason: T.any(String, Symbol, Hash),
        ignored: T.nilable(T::Boolean)
      }
    end

    # The perform method actually writes the subscriber information for the new thread, which was gathered by .copy_thread_subscribers
    # DO NOT CALL THIS METHOD DIRECTLY use Newsies::CopyThreadSubscribersJob.copy_thread_subscribers
    #
    # list_type - String type of list e.g. "Repository"
    # list_id - Integer of list
    # thread_type - String type of thred e.g. "Issue"
    # thread_id - Integer of thread
    # subscribers_info - Array<Integer> of [{ :user_id, :reason, :ignored }]
    #
    # Returns nothing.
    sig do
      params(
        list_type: String,
        list_id: Integer,
        thread_type: String,
        thread_id: Integer,
        subscribers_info: T::Array[SubscriberInfo]
      ).void
    end
    def perform(list_type, list_id, thread_type, thread_id, subscribers_info)
      newsies_list = List.new(list_type, list_id)
      newsies_thread = Thread.new(thread_type, thread_id, list: newsies_list) # rubocop:disable GitHub/ThreadUse

      thread = T.let(nil, T.nilable(ActiveRecord::Base))
      list = T.let(nil, T.nilable(ActiveRecord::Base))

      @trace_attributes = {
        "gh.notifications.list.type" => list_type,
        "gh.notifications.list.id" => list_id,
        "gh.notifications.thread.type" => thread_type,
        "gh.notifications.thread.id" => thread_id
      }

      thread = thread_type.constantize.find_by_id(thread_id) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      list = list_type.constantize.find_by_id(list_id)

      subscribers_info.each_slice(BATCH_SIZE) do |_batch|
        ThreadSubscription.throttle do
          subscribers_info.each do |subscriber_info|
            begin
              GitHub.tracer.in_span("perform.batch", kind: :internal, attributes: trace_attributes) do
                with_write do
                  ThreadSubscription.create({
                    list_type: newsies_thread.list_type,
                    list_id: newsies_thread.list_id,
                    thread_key: newsies_thread.key,
                    created_at: Time.now.utc
                  }.merge(subscriber_info))
                end

                if thread.nil?
                  GitHub.logger.info("can't copy thread in copy_thread_subscribers thread is nil", {
                    "code.namespace" => "CopyThreadSubscribersJob",
                    "code.function" => "perform",
                    "gh.notifications.system" => "notifyd"
                  })
                  return
                end

                if list.nil?
                  GitHub.logger.info("can't copy list in copy_thread_subscribers list is nil", {
                    "code.namespace" => "CopyThreadSubscribersJob",
                    "code.function" => "perform",
                    "gh.notifications.system" => "notifyd"
                  })
                  return
                end

                sync_thread_to_notifyd(subscriber_info, list, thread)
              end
            rescue ActiveRecord::RecordNotUnique
              # If user already subscribed just ignore this
            end
          end
        end
      end
    end

    # sig { params(subscriber_info: SubscriberInfo, list: ActiveRecord::Base, thread: ActiveRecord::Base).void }
    def sync_thread_to_notifyd(subscriber_info, list, thread)
      user_id = subscriber_info[:user_id]
      is_ignored = subscriber_info[:ignored]
      reason = subscriber_info[:reason]

      user = with_read { User.find_by(id: user_id) }

      if is_ignored
        send_to_notifyd = thread.try(:unsubscribe_in_notifyd?, user)
        return unless send_to_notifyd

        handle_errors(response_class: Notifyd::Responses::Boolean, method: "notifyd_unsubscribe_from_thread") do
          Notifyd::SubscriptionsHelper.new.notifyd_unsubscribe_from_thread(user, thread)
        end
      else
        return if reason.nil? || reason.empty?
        normalized_reason = Notifications::Subscriptions.valid_reason_from(reason)

        return if normalized_reason.nil? || normalized_reason.empty?

        send_to_notifyd = thread.try(:subscribe_in_notifyd?, user, normalized_reason)
        return unless send_to_notifyd

        handle_errors(response_class: Notifyd::Responses::Boolean, method: "notifyd_subscribe_to_thread") do
          Notifyd::SubscriptionsHelper.new.notifyd_subscribe_to_thread(user, list, thread, normalized_reason)
        end
      end
    end

    private

    def handle_errors(response_class: nil, method:, &block)
      notify_system = "notifyd"
      begin
        result = yield
        GitHub.dogstats.increment("notifyd.copy_subscribers_jobs.#{method}", tags: ["success:#{result}"])
        result
      rescue => e # rubocop:todo Lint/GenericRescue
        GitHub.dogstats.increment("notifyd.copy_subscribers_jobs.#{method}", tags: ["success:false"])
        GitHub.dogstats.increment("notifications.subscriptions.exceptions", tags: ["system:#{notify_system}", "scenario:copy_thread_subscribers"])
        NotificationsFailbot.report(e, "service.name": notify_system, "code.namespace": "copy_thread_subscribers", "code.function": method)
      end
    end
  end
end
