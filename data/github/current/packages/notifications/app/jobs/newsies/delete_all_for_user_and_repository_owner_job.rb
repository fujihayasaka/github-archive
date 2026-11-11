# typed: true
# frozen_string_literal: true

module Newsies
  # Deletes repository subscriptions for a user from a specific owner. Handles three
  # subscription types: "watching" (ListSubscription, includes notifyd sync), "custom"
  # (ThreadTypeSubscription), and "ignoring" (ignored ListSubscription).
  #
  # Enqueued by: Newsies::Service via
  # GitHub.newsies.async_delete_all_for_user_and_repository_owner, and
  # NotificationsController from the notification settings UI.
  class DeleteAllForUserAndRepositoryOwnerJob < MaintenanceBaseJob
    use_replicas ApplicationRecord::IamAbilities,
      ApplicationRecord::Mysql1,
      ApplicationRecord::Mysql2,
      ApplicationRecord::Repositories

    # user_id - Integer user to act on
    # owner_id - Integer repository owner ID
    # subscription_type - String type ( watching, custom, none and ignoring ) of subscription group to delete
    # skip_notifyd - deprecated
    def perform(user_id, owner_id, subscription_type, skip_notifyd: false)
      owner = User.find_by(id: owner_id)
      return unless owner
      trace_attributes = { "gh.user.id" => user_id, "gh.repo.owner.id" => owner_id, "gh.notifications.subscription.type" => subscription_type }

      GitHub.tracer.in_span("delete_all", kind: :internal, attributes: trace_attributes) do
        owner.repositories.select(:id).in_batches(of: BATCH_SIZE) do |batched_scope|
          batched_lists = batched_scope.map { |list| List.new(List.to_type(list), List.to_id(list)) }

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
          when "custom"
            GitHub.tracer.in_span("thread_type_subscription_delete_all.custom", kind: :internal) do
              with_write do
                ThreadTypeSubscription.throttle do
                  ThreadTypeSubscription.unsubscribe_from_all_thread_types_for_multiple_lists(user_id, batched_lists)
                end
              end
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
          else
            GitHub.tracer.in_span("list_subscription_delete_all.other", kind: :internal) do
              with_write { ListSubscription.for_user(user_id).for_lists(batched_lists).delete_all }
            end
          end
        end
      end
    end
  end
end
