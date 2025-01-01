# typed: false
# frozen_string_literal: true

module Newsies
  # Delete all repository subscriptions and notifications for a user
  class DeleteAllForUserAndRepositoryOwnerJob < MaintenanceBaseJob
    # user_id - Integer user to act on
    # owner_id - Integer repository owner ID
    # subscription_type - String type ( watching, custom, none and ignoring ) of subscription group to delete
    def perform(user_id, owner_id, subscription_type)
      owner = User.find(owner_id)
      return unless owner
      user = User.new(id: user_id)
      sync_notifyd = GitHub.flipper[:notifyd_sync_respository_list].enabled?(user)
      subscription_service = Notifyd::SubscriptionsService.new(user, true, ["job": "delete_all_for_user_and_repository_owner"])
      routing_service = Notifyd::RoutingSettingsService.new(user, true, ["job": "delete_all_for_user_and_repository_owner"])
      trace_attributes = { "gh.user.id" => user_id, "gh.repo.owner.id" => owner_id, "gh.notifications.subscription.type" => subscription_type, "gh.notifyd.should_sync" => sync_notifyd }

      GitHub.tracer.in_span("delete_all", kind: :internal, attributes: trace_attributes) do
        owner.repositories.select(:id).in_batches(of: BATCH_SIZE) do |batched_scope|
          batched_lists = batched_scope.map { |list| List.new(List.to_type(list), List.to_id(list)) }
          repositories = []
          if sync_notifyd
            repositories = batched_lists.select { |list| List.to_type(list) == "Repository" }
          end

          case subscription_type
          when "watching"
            GitHub.tracer.in_span("list_subscription_delete_all.watching", kind: :internal) do
              with_write do
                ListSubscription.throttle do
                  ListSubscription.for_user(user_id)
                    .for_lists(batched_lists)
                    .excluding_ignored
                    .delete_all
                end
              end
            end
            repositories.each do |list|
              subscription_service.delete([
                { name: "category", value: "all" },
                { name: "repository_id", value: List.to_id(list).to_s },
              ])
            end
          when "custom"
            GitHub.tracer.in_span("thread_type_subscription_delete_all.custom", kind: :internal) do
              with_write do
                ThreadTypeSubscription.throttle do
                  ThreadTypeSubscription.unsubscribe_from_all_thread_types_for_multiple_lists(user_id, batched_lists)
                end
              end
            end
            repositories.each do |list|
              subscription_service.delete([
                { name: "category", value: "thread_type" },
                { name: "repository_id", value: List.to_id(list).to_s },
              ])
            end
          when "ignoring"
            GitHub.tracer.in_span("list_subscription_delete_all.ignoring", kind: :internal) do
              with_write do
                ListSubscription.throttle do
                  ListSubscription.for_user(user_id)
                    .for_lists(batched_lists)
                    .only_ignored
                    .delete_all
                end
              end
            end
            repositories.each do |list|
              routing_service.delete([
                { name: "watcher_scenario", value: "true" },
                { name: "repository_id", value: List.to_id(list).to_s },
              ])
            end
          else
            GitHub.tracer.in_span("list_subscription_delete_all.other", kind: :internal) do
              with_write { ListSubscription.for_user(user_id).for_lists(batched_lists).delete_all }
            end
            repositories.each do |list|
              repository_id = List.to_id(list).to_s
              subscription_service.delete([
                { name: "watcher_scenario", value: "true" },
                { name: "repository_id", value: repository_id },
              ])
              routing_service.delete([
                { name: "watcher_scenario", value: "true" },
                { name: "repository_id", value: repository_id },
              ])
            end
          end
        end
      end
    end
  end
end
