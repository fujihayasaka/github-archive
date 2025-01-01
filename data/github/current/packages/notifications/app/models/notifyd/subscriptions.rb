# typed: true
# frozen_string_literal: true

module Notifyd
  module Subscriptions
    include Notifyd::NetworkHelper

    RS = Notifyd::Proto::RoutingSettings

    ThreadMissingError = Class.new(StandardError)

    def notifyd_subscribe_to_thread(user, list, thread, reason = nil)
      Notifyd::Responses::Boolean.new do
        raise ThreadMissingError unless thread.present?
        next false if !thread.respond_to?(:subscribable_by?) || !thread.subscribable_by?(user)

        tags = thread_subscription_tags(reason: reason, thread: thread, list: list)
        notifyd_primary = notifyd_primary?(user, thread)
        subscriptions_service = Notifyd::SubscriptionsService.new(user, notifyd_primary, tags)
        rs_service = Notifyd::RoutingSettingsService.new(user, notifyd_primary, tags)

        instrument("notifyd_subscribe_to_thread", tags) do
          success = subscriptions_service.save([build_thread_subscription(user, list, thread, reason)])
          next false unless success
          # delete any existing routing settings for this thread
          rs_service.delete(thread_subscription_custom_fields(thread))
        end
      end
    end

    def notifyd_unsubscribe_from_thread(user, thread)
      Notifyd::Responses::Boolean.new do
        instrument("notifyd_unsubscribe_from_thread", ["thread_type:#{thread_type(thread)}"]) do
          notifyd_primary = notifyd_primary?(user, thread)

          subscriptions_service = Notifyd::SubscriptionsService.new(user, notifyd_primary)
          success = subscriptions_service.delete(thread_subscription_custom_fields(thread))

          next false unless success

          rs_service = Notifyd::RoutingSettingsService.new(user, notifyd_primary)
          rs_service.save([build_ignore_setting(user, thread)])
        end
      end
    end

    def notifyd_subscription_status(user, list, thread)
      Notifyd::Responses::ThreadSubscription.new do
        instrument("notifyd_subscription_status", ["thread_type:#{thread_type(thread)}"]) do
          subscriptions_service = Notifyd::SubscriptionsService.new(user, true)
          rs_service = Notifyd::RoutingSettingsService.new(user, true)

          thread_subscription = subscriptions_service.get_thread_subscription(thread_type(thread), thread.id)
          routing_settings = rs_service.get_thread_settings(thread_type(thread), thread.id)

          notifyd_thread_subscription = Notifyd::ThreadSubscription.new(user, thread, thread_subscription, routing_settings)

          notifyd_thread_label_subscription = nil
          if thread.is_a?(Issue) && GitHub.flipper[:notifyd_label_subscriptions].enabled?(user) && !notifyd_thread_subscription.valid?
            thread_label_subscriptions = subscriptions_service.get_thread_label_subscriptions(list, thread)
            notifyd_thread_label_subscription = thread_label_subscriptions.filter do |label_subscription|
              if label_subscription.valid?
                break label_subscription
              end
              nil
            end if thread_label_subscriptions.length > 0

            # This can happen if we have label subscriptions in Notifyd but they are all invalid
            # We don't want to return array as it will break the caller's logic
            if notifyd_thread_label_subscription.is_a?(Array)
              notifyd_thread_label_subscription = nil
            end

          end
          notifyd_thread_label_subscription || notifyd_thread_subscription
        end
      end
    end

    def notifyd_delete_thread_subscription(user, thread)
      unsubscribe_enabled = thread&.respond_to?(:unsubscribe_in_notifyd?) && thread&.unsubscribe_in_notifyd?(user)
      return Notifyd::Responses::Boolean.new { true } unless unsubscribe_enabled

      result = instrument("notifyd_delete_thread_subscription", ["thread_type:#{thread_type(thread)}"]) do
        # We intend to use this workflow from background jobs only
        raise_errors = true

        subscriptions_service = Notifyd::SubscriptionsService.new(user, true)
        subscription_delete_result = subscriptions_service.delete(thread_subscription_custom_fields(thread))

        next false unless subscription_delete_result

        rs_service = Notifyd::RoutingSettingsService.new(user, true)
        rs_delete_result = rs_service.delete(thread_subscription_custom_fields(thread))

        rs_delete_result
      end

      Notifyd::Responses::Boolean.new { result }
    end

    def notifyd_schedule_delete_thread_subscriptions(user_id:, thread_subscription_ids:)
      instrument("schedule_delete_thread_subscriptions") do
        subscription_batches = Newsies::ThreadSubscription
          .for_user(user_id)
          .where(id: thread_subscription_ids)
          .in_batches(of: Newsies::ThreadSubscription::DELETE_BATCH_SIZE)

        T.must(subscription_batches).each do |batch|
          to_delete_thread_subscriptions = []

          batch.map do |thread_subscription|
            to_delete_thread_subscriptions << {
              user_id: user_id,
              list_type: thread_subscription.list_type,
              list_id: thread_subscription.list_id,
              thread_key: thread_subscription.thread_key
            }
          end

          # We run deletions on Notifyd in Background job
          Notifyd::SyncDeleteThreadSubscriptionsJob.perform_later(
            user_id: user_id,
            subscriptions_to_delete: to_delete_thread_subscriptions
          )
        end
      end

      Response.new { nil }
    end

    private

    def notifyd_primary?(user, thread)
      thread.respond_to?(:notifyd_primary?) && thread.notifyd_primary?(user)
    end

    def instrument(method_name, tags = nil)
      GitHub.tracer.in_span(method_name, kind: :internal) do
        success = yield

        tags = Array(tags) << "success:#{success}"
        GitHub.dogstats.increment("notifyd.subscriptions.#{method_name}", tags: tags)

        success
      end
    end

    def thread_subscription_tags(reason:, thread:, list:)
      ["reason:#{reason || "NONE"}", "thread_type:#{thread_type(thread)}", "list_type:#{list_type(list)}"]
    end

    def build_ignore_setting(user, thread)
      # TODO(abeaumont): We'll keep the legacy format for filters for Gists for now.
      # Once they are validated with Issues we can also enable for Gists which are already GA.
      if thread_type(thread) == "gist"
        filters = %w[comment author manual].map do |reason|
          RS::Filter.new(
            reason: reason,
            subject_type: "any",
            trigger: "any"
          )
        end
      else
        filters = [
          RS::Filter.new(
            subject_type: "any",
            trigger: "any",
            reason: "any",
            match_rules: [
              RS::MatchRule.new(attribute: "thread_participant_activity", value: "true", match_rule: "eq"),
              RS::MatchRule.new(value: "notify_muted", match_rule: "not_in_reason_group"),
            ]
          )]
      end
      RS::RoutingSetting.new(
          user_id: user.id,
          name: "ignore",
          topics: [RS::Topic.new(type: thread_type(thread), value: thread.id.to_s)],
          filters: filters,
          channels: [RS::Channel.new(name: "ALL", enabled: false)],
          custom_fields: thread_subscription_custom_fields(thread)
      )
    end

    def build_thread_subscription(user, list, thread, reason)
      {
        reason: reason,
        topics: [{ type: thread_type(thread), value: thread.id.to_s }],
        filters: [
          {
            subject_type: "any",
            trigger: "any",
            match_rules: [
              { attribute: "thread_participant_activity", value: "true", match_rule: "eq" },
            ],
          }
        ],
        custom_fields: thread_subscription_custom_fields(thread)
      }
    end

    def thread_subscription_custom_fields(thread)
      fields = [
        { name: "category", value: "thread" },
        { name: "thread_type", value: thread_type(thread) },
        { name: "thread_id", value: thread.id.to_s },
        { name: "owner_type", value: list_type(thread.notifications_list) },
        { name: "owner_id", value: thread.notifications_list.id.to_s },
      ]
      if list_type(thread.notifications_list) == "repository"
        fields << { name: "repository_id", value: thread.notifications_list.id.to_s }
      end
      fields
    end

    def notifyd_client
      @notifyd_client ||= Notifyd.client
    end

    def thread_type(thread)
      thread.class.name.underscore
    end

    def list_type(list)
      list.class.name.underscore
    end
  end

end
