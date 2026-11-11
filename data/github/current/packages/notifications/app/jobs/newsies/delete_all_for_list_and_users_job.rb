# typed: true
# frozen_string_literal: true

module Newsies
  # Delete all subscriptions and notifications for a list and a given set of users
  class DeleteAllForListAndUsersJob < MaintenanceBaseJob
    # list_type - String newsies list type
    # list_id   - Integer newsies list id
    # user_ids   - Array of Integer user ids
    # restorable_id - Integer ID of a VisibilityChangedRestorable, if applicable

    resolve_tenant_context do |list_type, list_id, _|
      Notifications::TenantContext.resolve_tenant_for_list(list_type: list_type, list_id: list_id)
    end

    def perform(list_type, list_id, user_ids, restorable_id: nil)
      list = List.new(list_type, list_id)
      restorable_storage = RestorableStorage.create_if_needed(restorable_id, list)
      trace_attributes = {
        "gh.notifications.list.id" => list_id,
        "gh.notifications.list.type" => list_type,
        "gh.notifications.job.user.count" => user_ids.size
      }

      GitHub.tracer.in_span("perform", kind: :internal, attributes: trace_attributes) do

        user_ids.each_slice(BATCH_SIZE) do |batched_user_ids|
          restorable_storage&.store_watched_repositories(batched_user_ids)
          GitHub.tracer.in_span("list_subscription", kind: :internal) do
            with_write do
              ListSubscription.throttle do
                ListSubscription.for_list(list).for_users(batched_user_ids).delete_all
              end
            end
          end

          restorable_storage&.store_custom_watched_repositories(batched_user_ids)
          GitHub.tracer.in_span("delete_thread_type_subscriptions", kind: :internal) do
            with_write do
              ThreadTypeSubscription.throttle do
                ThreadTypeSubscription.for_list(list).for_users(batched_user_ids).delete_all
              end
            end
          end

          GitHub.tracer.in_span("delete_thread_subscriptions", kind: :internal) do
            ThreadSubscription.for_list(list)
                              .for_users(batched_user_ids)
                              .in_batches(of: BATCH_SIZE) do |batched_scope|
              restorable_storage&.store_watched_repository_threads(batched_scope)
              with_write do
                delete_thread_subscription_events(batched_scope.pluck(:id))
                ThreadSubscription.throttle { batched_scope.delete_all }
              end
            end
          end

          GitHub.tracer.in_span("delete_notification_entries", kind: :internal) do
            NotificationEntry.for_list(list)
                             .for_users(batched_user_ids)
                             .in_batches(of: BATCH_SIZE) do |scope|
              with_write do
                NotificationEntry.throttle { scope.delete_all }
              end
            end
          end

          GitHub.tracer.in_span("delete_saved_notification_entries", kind: :internal) do
            SavedNotificationEntry.for_list(list)
                                  .for_users(batched_user_ids)
                                  .in_batches(of: BATCH_SIZE) do |scope|
              with_write do
                SavedNotificationEntry.throttle { scope.delete_all }
              end
            end
          end
        end

        restorable_storage&.mark_batch_saved
      end
    end

    # Inner class that implements the storage of removed watcher data for possible later restoration through
    # stafftools (within 90 days). See the restorables package for more details.
    class RestorableStorage
      include GitHub::Memoizer

      # Return an instance only if all of the conditions to persist restorable data are met:
      # - restorable_id was provided during job launch, which only happens from the repository visibility
      #     orchestration
      # - list is a valid Repository
      #
      # Otherwise, return nil so all of this is skipped.
      sig do
        params(restorable_id: T.nilable(Integer), list: Newsies::List)
          .returns(T.nilable(RestorableStorage))
      end
      def self.create_if_needed(restorable_id, list)
        return nil unless restorable_id
        return nil unless list.type == "Repository"

        repository = Repositories.domain.by_id(list.id)
        return nil unless repository

        new(restorable_id, list, repository)
      end

      sig { params(user_ids: T::Array[Integer]).void }
      def store_watched_repositories(user_ids)
        return unless user_ids.any?

        GitHub.tracer.in_span("restorable_watched_repository_storage", kind: :internal) do
          subscriptions = ListSubscription.for_list(list).for_users(user_ids).map do |list_sub|
            Restorables::WatchedRepositorySubscription.new(
              id: T.must(repository.id),
              ignored: list_sub.ignored?,
              subscriber_id: list_sub.user_id,
              subscribed_at: list_sub.created_at
            )
          end
          return if subscriptions.empty?

          ActiveRecord::Base.connected_to(role: :writing) do
            domain.save_watched_repositories(
              restorable_id: restorable_id,
              repositories: subscriptions
            )
          end
        end
      end

      sig { params(user_ids: T::Array[Integer]).void }
      def store_custom_watched_repositories(user_ids)
        return unless user_ids.any?

        GitHub.tracer.in_span("restorable_custom_watched_repository_storage", kind: :internal) do
          subscriptions = ThreadTypeSubscription.for_list(list).for_users(user_ids).map do |thread_type_sub|
            Restorables::CustomWatchedRepositorySubscription.new(
              user_id: thread_type_sub.user_id,
              thread_type: thread_type_sub.thread_type,
              original_created_at: thread_type_sub.created_at
            )
          end
          return unless subscriptions.any?

          ActiveRecord::Base.connected_to(role: :writing) do
            domain.save_custom_watched_repositories(
              restorable_id: restorable_id,
              subscriptions: subscriptions,
            )
          end
        end
      end

      sig { params(thread_subscriptions: ActiveRecord::Relation).void }
      def store_watched_repository_threads(thread_subscriptions)
        return unless thread_subscriptions.any?

        GitHub.tracer.in_span("restorable_watched_repository_threads_storage", kind: :internal) do
          threads = thread_subscriptions.map do |thread_sub|
            Restorables::WatchedRepositoryThreadSubscription.new(
              user_id: thread_sub.user_id,
              ignored: thread_sub.ignored?,
              reason: thread_sub.reason,
              thread_key: thread_sub.thread_key,
            )
          end
          return if threads.empty?

          ActiveRecord::Base.connected_to(role: :writing) do
            domain.save_watched_repository_threads(
              restorable_id: restorable_id,
              threads: threads
            )
          end
        end
      end

      sig { void }
      def mark_batch_saved
        ActiveRecord::Base.connected_to(role: :writing) do
          domain.report_saving_watchers_progress(restorable_id: restorable_id)
        end
      end

      private

      sig do
        params(
          restorable_id: Integer,
          list: Newsies::List,
          repository: Repositories::IRepository
        ).void
      end
      def initialize(restorable_id, list, repository)
        @restorable_id = restorable_id
        @list = list
        @repository = repository
      end

      sig { returns(Integer) }
      attr_reader :restorable_id

      sig { returns(Newsies::List) }
      attr_reader :list

      sig { returns(Repositories::IRepository) }
      attr_reader :repository

      sig { returns(Restorables::Domain::VisibilityChangedRepositories) }
      def domain
        Restorables.domain.visibility_changed_repositories
      end
    end
  end
end
