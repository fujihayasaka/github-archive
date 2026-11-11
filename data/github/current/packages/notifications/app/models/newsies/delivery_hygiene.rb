# typed: true
# frozen_string_literal: true

module Newsies
  # DeliveryHygiene controls whether a delivery is healthy or not.
  #
  # It returns an object that responds to whether a delivery has to halt and
  # also whether it needs cleanup.
  #
  # Cleanup for a healthy delivery is a noop
  #
  # We do this so that we make sure that we can halt
  #
  # NOTE: (@franciscoj 25/08/2023) it intentionally avoids any memoization as
  # it is meant to be called on each iteration of a loop to force checking
  # the health on each iteration.
  class DeliveryHygiene
    class Check
      def initialize(reason, delivery)
        @reason = reason
        @delivery = delivery
      end

      def halt?
        reason == :unhealthy_delivery
      end

      def cleanup
        log_context("code.function" => "cleanup") do
          case reason
          when :unhealthy_delivery
            GitHub.newsies.async_delete_all_for_thread(delivery.list, delivery.thread)

            GitHub.dogstats.increment("newsies.cleanup.delivery", tags: %W[thread_type:#{delivery.thread_type} list_type:#{delivery.list_type} cleanup_type:unhealthy])
            GitHub.logger.info("enqueueing delete_all_for_thread")
          when :spammy_delivery
            UpdateNotificationsSpamStatusJob.perform_later(
              delivery.list_type,
              delivery.list_id,
              delivery.thread_type,
              delivery.thread_id,
            )

            GitHub.logger.info("enqueueing update_notifications_spam_status_job")
            GitHub.dogstats.increment("newsies.cleanup.delivery", tags: %W[thread_type:#{delivery.thread_type} list_type:#{delivery.list_type} cleanup_type:spam])
          end
        end
      end

      private

      attr_reader :reason
      attr_reader :delivery

      def log_context(extra = {})
        GitHub.logger.with_named_tags({
          "code.namespace": "Newsies::DeliveryHygiene::Check",
          "gh.notifications.list.id": delivery.list_id,
          "gh.notifications.list.class": delivery.list_type,
          "gh.notifications.thread.id": delivery.thread_id,
          "gh.notifications.thread.class": delivery.thread_type,
        }.merge(extra)) do
          yield
        end
      end
    end

    def initialize(delivery)
      @delivery = delivery
    end

    def halt?
      check.halt?
    end

    def cleanup
      check.cleanup
    end

    private

    attr_reader :delivery

    def check
      Check.new(reason, delivery)
    end

    def reason
      return :unhealthy_delivery if unhealthy?
      return :spammy_delivery if spammy?

      :continue
    end

    def spammy?
      log_context("code.function" => "spammy?") do
        thread = delivery.thread.try(:reload) # domain-isolation-query-violation:ignore:packages/issues (SELECT)

        if thread.try(:spammy?)
          GitHub.dogstats.increment("newsies.delivery.thread_spammy", tags: %W[thread_type:#{delivery.thread_type} list_type:#{delivery.list_type}])
          GitHub.logger.info("found spammy thread during delivery")

          return true
        end

        return false
      end
    end

    def unhealthy?
      log_context("code.function" => "unhealthy?") do
        list = delivery.list
        unless list.class.exists?(list.id)
          GitHub.dogstats.increment("newsies.delivery.list_deleted", tags: %W[thread_type:#{delivery.thread_type} list_type:#{delivery.list_type}])
          GitHub.logger.info("found deleted list during delivery")

          return true
        end

        thread = delivery.thread
        # some threads (like Commit) are not ActiveRecord models
        return false unless thread.class.respond_to?(:exists?)

        unless thread.class.exists?(thread.id) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
          GitHub.dogstats.increment("newsies.delivery.thread_deleted", tags: %W[thread_type:#{delivery.thread_type} list_type:#{delivery.list_type}])
          GitHub.logger.info("found deleted thread during delivery")

          return true
        end

        false
      end
    end

    def log_context(extra = {})
      GitHub.logger.with_named_tags({
        "code.namespace": "Newsies::DeliveryHygiene",
        "gh.notifications.list.id": delivery.list_id,
        "gh.notifications.list.class": delivery.list_type,
        "gh.notifications.thread.id": delivery.thread_id,
        "gh.notifications.thread.class": delivery.thread_type,
        "gh.notifications.early_halt": true
      }.merge(extra)) do
        yield
      end
    end
  end
end
