# typed: true
# frozen_string_literal: true

module Newsies
  # Deletes all repository (or team) subscriptions for a user across all repositories/teams.
  # Handles three subscription types: "watching" (non-ignored ListSubscription, includes
  # notifyd sync), "custom" (ThreadTypeSubscription), and "ignoring" (ignored ListSubscription).
  #
  # Enqueued by: Newsies::Service via
  # GitHub.newsies.async_delete_for_user_and_all_repositories, and
  # NotificationsController from the notification settings UI.
  class DeleteForUserAndAllRepositoriesJob < MaintenanceBaseJob
    use_replicas ApplicationRecord::IamAbilities,
      ApplicationRecord::Mysql1,
      ApplicationRecord::Mysql2

    # user_id - Integer user to act on
    # list_type - String type of the notifications list class. Hardcoded to `Repository`.
    # subscription_type - String type ( watching, custom, none and ignoring ) of subscription group to delete
    # skip_notifyd - deprecated
    def perform(user_id, list_type, subscription_type, skip_notifyd: false)
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
        when "custom"
          ThreadTypeSubscription
            .for_user(user_id)
            .where(list_type: list_type)
            .in_batches(of: BATCH_SIZE) do |scope|
            with_write { ThreadTypeSubscription.throttle { scope.delete_all } }
          end
        when "ignoring"
          ListSubscription
            .for_user(user_id)
            .where(list_type: list_type)
            .only_ignored
            .in_batches(of: BATCH_SIZE) do |scope|
            with_write { ListSubscription.throttle { scope.delete_all } }
          end
        end
      end
    end
  end
end
