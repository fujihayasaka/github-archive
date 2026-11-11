# typed: true
# frozen_string_literal: true

module Notifyd
  module Subscriptions
    RS = Notifyd::Proto::RoutingSettingsV2

    ThreadMissingError = Class.new(StandardError)
    UnavailableError = Class.new(Resiliency::Response::UnavailableError)

    def self.subscribe_to_thread(user, list, thread, reason = nil)
      Notifyd::Responses::Boolean.new do
        raise ThreadMissingError unless thread.present?
        next false if !thread.respond_to?(:subscribable_by?) || !thread.subscribable_by?(user)
        notifyd_primary = thread.respond_to?(:notifyd_primary?) && thread.notifyd_primary?(user)

        tags = thread_subscription_tags(reason: reason, thread: thread, list: list)

        instrument("notifyd_subscribe_to_thread", tags) do
          success = Notifyd::Subscriptions::SubscriptionsService.batch_replace(user.id, [build_thread_subscription(user, list, thread, reason)])
          raise UnavailableError if !success && notifyd_primary
          next false unless success

          # delete any existing routing settings for this thread
          Notifyd::Settings::RoutingSettingsService.delete(
            user.id,
            thread_subscription_custom_field_groups(thread)
          )
        end
      end
    end

    def self.unsubscribe_from_thread(user, thread)
      Notifyd::Responses::Boolean.new do
        notifyd_primary = thread.respond_to?(:notifyd_primary?) && thread.notifyd_primary?(user)

        instrument("notifyd_unsubscribe_from_thread", ["thread_type:#{thread_type(thread)}"]) do
          success = Notifyd::Subscriptions::SubscriptionsService.delete(user.id, thread_subscription_custom_fields(thread))
          raise UnavailableError if !success && notifyd_primary

          next false unless success

          Notifyd::Settings::RoutingSettingsService.replace(
            user.id,
            [build_ignore_setting(thread)],
            thread_subscription_custom_field_groups(thread)
          )
        end
      end
    end

    def self.subscription_status(user, list, thread)
      Notifyd::Responses::ThreadSubscription.new do
        instrument("notifyd_subscription_status", ["thread_type:#{thread_type(thread)}"]) do
          thread_subscription = Notifyd::Subscriptions::SubscriptionsService.thread_subscription(user.id, thread_type(thread), thread.id)
          raise UnavailableError if thread_subscription.nil?

          mute_setting = Notifyd::Settings::RoutingSettingsService.thread_mute_setting(user.id, thread_type(thread), thread.id)
          raise UnavailableError if mute_setting.nil?

          notifyd_thread_subscription = Notifyd::ThreadSubscription.new(user, thread, thread_subscription, mute_setting)

          notifyd_thread_label_subscription = nil
          if thread.is_a?(Issue) && user.feature_flag_enabled?(:notifyd_label_subscriptions, default: false) && !notifyd_thread_subscription.valid?
            thread_label_subscriptions = Notifyd::Subscriptions::SubscriptionsService.thread_label_subscriptions(user.id, list.id, thread.labels.map(&:id))
            raise UnavailableError if thread_label_subscriptions.nil?

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

    # We intend to use this workflow from background jobs only
    def self.delete_thread_subscription(user, thread)
      unsubscribe_enabled = thread&.respond_to?(:unsubscribe_in_notifyd?) && thread&.unsubscribe_in_notifyd?(user)
      return Notifyd::Responses::Boolean.new { true } unless unsubscribe_enabled

      result = instrument("notifyd_delete_thread_subscription", ["thread_type:#{thread_type(thread)}"]) do
        success = Notifyd::Subscriptions::SubscriptionsService.delete(user.id, thread_subscription_custom_fields(thread))
        raise UnavailableError unless success

        success = Notifyd::Settings::RoutingSettingsService.delete(
          user.id,
          thread_subscription_custom_field_groups(thread),
        )
        raise UnavailableError unless success
        true
      end

      Notifyd::Responses::Boolean.new { result }
    end

    def self.schedule_delete_thread_subscriptions(user_id:, thread_subscription_ids:)
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

    private_class_method def self.instrument(method_name, tags = nil)
      GitHub.tracer.in_span(method_name, kind: :internal) do
        success = yield

        tags = Array(tags) << "success:#{success}"
        GitHub.dogstats.increment("notifyd.subscriptions.#{method_name}", tags: tags)

        success
      end
    end

    private_class_method def self.thread_subscription_tags(reason:, thread:, list:)
      ["reason:#{reason || "NONE"}", "thread_type:#{thread_type(thread)}", "list_type:#{list_type(list)}"]
    end

    private_class_method def self.build_ignore_setting(thread)
      RS::Setting.new(
        name: "ignore",
        topics: [RS::Topic.new(type: thread_type(thread), value: thread.id.to_s)],
        filters: [
          RS::Filter.new(
            subject_type: "any",
            trigger: "any",
            reason: "any",
            match_rules: [
              RS::MatchRule.new(attribute: "thread_participant_activity", value: "true", match_rule: "eq"),
              RS::MatchRule.new(value: "notify_muted", match_rule: "not_in_reason_group"),
            ]
          )],
        channels: [RS::Channel.new(name: "ALL", enabled: false)],
        custom_fields: thread_subscription_custom_fields(thread)
      )
    end

    private_class_method def self.build_thread_subscription(user, list, thread, reason)
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

    private_class_method def self.thread_subscription_custom_fields(thread)
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

    private_class_method def self.thread_subscription_custom_field_groups(thread)
      fields = thread_subscription_custom_fields(thread)
      [{ fields: fields }]
    end

    private_class_method def self.thread_type(thread)
      thread.class.name.underscore
    end

    private_class_method def self.list_type(list)
      list.class.name.underscore
    end
  end
end
