# typed: true
# frozen_string_literal: true

module Newsies
  # Delete all repository subscriptions and notifications for a user
  class DeleteForUserAndAllRepositoriesJob < MaintenanceBaseJob
    NotifydError = Class.new(StandardError)
    RS = Notifyd::Proto::RoutingSettingsV2

    # user_id - Integer user to act on
    # list_type - String type of the notifications list class. Supported types are `Repository` and `Team`.
    # subscription_type - String type ( watching, custom, none and ignoring ) of subscription group to delete
    def perform(user_id, list_type, subscription_type)
      user = User.new(id: user_id)
      sync_notifyd = list_type == "Repository" && FeatureFlag.vexi.enabled?(:notifyd_sync_respository_list, user, default: true)
      subscription_service = Notifyd::SubscriptionsService.new(user, true, ["job": "delete_for_user_and_all_repositories"])

      trace_attributes = { "gh.user.id" => user_id, "gh.notifications.list.type" => list_type, "gh.notifications.subscription.type" => subscription_type }

      GitHub.tracer.in_span("delete_all_by_subscription_type", kind: :internal, attributes: trace_attributes) do
        case subscription_type
        when "watching"
          ListSubscription
            .for_user(user_id)
            .where(list_type: list_type)
            .excluding_ignored
            .in_batches(of: BATCH_SIZE) do |scope|

            with_write { ListSubscription.throttle { scope.delete_all } }
          end
          if sync_notifyd
            subscription_service.delete([{ name: "category", value: "all" }])
          end
        when "custom"
          ThreadTypeSubscription
            .for_user(user_id)
            .where(list_type: list_type)
            .in_batches(of: BATCH_SIZE) do |scope|

            with_write { ThreadTypeSubscription.throttle { scope.delete_all } }
          end
          if sync_notifyd
            subscription_service.delete([{ name: "category", value: "thread_type" }])
          end
        when "ignoring"
          ListSubscription
            .for_user(user_id)
            .where(list_type: list_type)
            .only_ignored
            .in_batches(of: BATCH_SIZE) do |scope|

            with_write { ListSubscription.throttle { scope.delete_all } }
          end
          if sync_notifyd
            success = Notifyd::Settings::RoutingSettingsService.delete(user_id, [RS::CustomFieldGroup.new(
              fields: [RS::CustomField.new(name: "watcher_scenario", value: "true")]
            )])
            raise NotifydError unless success
          end
        end
      end
    end
  end
end
