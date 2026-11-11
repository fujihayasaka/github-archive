# coding: utf-8
# typed: true
# frozen_string_literal: true

module Notifications
  module Subscriptions
    EXCEPTIONS_STAT = "notifications.subscriptions.exceptions"
    DIFFERENCE_STAT = "notifications.subscriptions.differences"

    class RepositorySubscriptionType < T::Enum
      enums do
        Watching = new("watching")
        Custom = new("custom")
        Ignoring = new("ignoring")
      end
    end

    # Subscribe a user to a thread.
    #
    # user    - A User.
    # list    - A list (ie: Repository).
    # thread  - A thread (ie: Issue, Commit, etc.).
    # reason  - Optional String, Symbol or Hash reason
    #           (ie: "mention", :mention, {:reason => :mention, :force => true}).
    # events  - Optional Array of String event names
    #
    # Returns true on success, false otherwise.
    def self.subscribe_to_thread(user, list, thread, reason = nil, events = [])
      GitHub.tracer.in_span("subscribe_to_thread", kind: :internal) do
        success = GitHub.dogstats.distribution_time("notifications.subscriptions.subscribe_to_thread") do
          reason_for_notifyd = valid_reason_from(reason)
          if reason == "manual"
            GitHub.dogstats.increment("subscribe_to_thread.manual.count", tags: ["thread:#{thread.class.name}"])
          end
          send_to_notifyd = thread&.respond_to?(:subscribe_in_notifyd?) && thread&.subscribe_in_notifyd?(user, reason_for_notifyd)
          notifyd_primary = thread&.respond_to?(:notifyd_primary?) && thread.notifyd_primary?(user)

          newsies_response = handle_errors(raise_errors: !notifyd_primary, method: "subscribe_to_thread") do
            GitHub.newsies.subscribe_to_thread(user, list, thread, reason, events)
          end

          next newsies_response&.success? unless send_to_notifyd

          notifyd_response = handle_errors(type: :notifyd, method: "subscribe_to_thread") do
            response = Notifyd::Subscriptions.subscribe_to_thread(user, list, thread, reason_for_notifyd)
            raise Notifyd::Subscriptions::UnavailableError if notifyd_primary && !response&.success?

            response
          end

          if !!notifyd_response != !!newsies_response
            GitHub.dogstats.increment(DIFFERENCE_STAT, tags: ["method:subscribe_to_thread"])
            GitHub.logger.info("found differences in results between notifyd and newsies", {
              "code.namespace" => "Notifications::Subscriptions",
              "code.function" => "subscribe_to_thread",
              "gh.notifications.response" => !!newsies_response,
              "gh.notifyd.response" => !!notifyd_response
            })
          end
          notifyd_primary ? !!notifyd_response&.success? : !!newsies_response&.success?
        end
        tags = ["success:#{success}"]
        GitHub.dogstats.increment("notifications.subscriptions.subscribe_to_thread.count", tags:)
        success
      end
    end

    # Unsubscribe a user from a thread.
    #
    # user    - A User.
    # thread  - A thread (ie: Issue, Commit, etc.).
    #
    # Returns true on success, false otherwise.
    def self.unsubscribe_from_thread(user, thread)
      GitHub.tracer.in_span("unsubscribe_from_thread", kind: :internal) do
        code_path = T.let(nil, T.nilable(String))
        success = GitHub.dogstats.distribution_time("notifications.subscriptions.unsubscribe_from_thread") do
          notifyd_primary = thread&.respond_to?(:notifyd_primary?) && thread.notifyd_primary?(user)

          newsies_list = Newsies::List.to_object(thread.notifications_list)
          newsies_thread = Newsies::Thread.to_object(thread.notifications_thread, list: newsies_list)

          newsies_response = handle_errors(raise_errors: !notifyd_primary, method: "unsubscribe_from_thread") do
            Newsies::Response.new do
              # If the user is subscribed to the list, then we must insert an "ignoring" thread
              # subscription to block notifications that would otherwise be sent to the list.
              #
              # If the user is ignoring the list, we fall through and delete the thread subscription
              # at the end.
              if Newsies::ListSubscription.for_user(user.id).for_list(newsies_list).excluding_ignored.exists?
                code_path = "list_ignore"
                Newsies::ThreadSubscription.ignore(user.id, newsies_thread)

              # If the user is subscribed to the thread type, then we must insert
              # an "ignoring" record for the thread to block notifications that
              # would otherwise be sent due to the thread type subscription
              elsif Newsies::ThreadTypeSubscription.for_user(user.id).for_list(newsies_list).for_thread_type(newsies_thread.subscription_type).exists?
                code_path = "thread_type_ignore"
                Newsies::ThreadSubscription.ignore(user.id, newsies_thread)

              # The user has no list-level subscriptions, so to unsubscribe from
              # future notifications on this thread (until they are re-subscribed)
              # we can simply delete the thread subscription
              else
                code_path = "delete"
                Newsies::ThreadSubscription.for_user(user.id).for_thread(newsies_thread).destroy_all
              end
            end
          end

          return false unless newsies_response&.success?

          if thread&.respond_to?(:unsubscribe_in_notifyd?) && thread&.unsubscribe_in_notifyd?(user)
            notifyd_response = handle_errors(type: :notifyd, method: "unsubscribe_from_thread") do
              response = Notifyd::Subscriptions.unsubscribe_from_thread(user, thread)
              raise Notifyd::Subscriptions::UnavailableError if notifyd_primary && !response&.value

              response
            end
            notifyd_success = !!notifyd_response&.value
            GitHub.dogstats.increment("notifications.subscriptions.notifyd.unsubscribe_from_thread", tags: ["success:#{notifyd_success}"])
          end

          # Notify websocket subscribers of the subscription status change.
          # Commits don't respond to #id properly, so skip them.
          unless newsies_thread.type == "Grit::Commit"
            NotifySubscriptionStatusChangeJob.perform_later(
              user.id,
              newsies_list.id,
              newsies_thread.id,
              { reason: "thread subscription status changed" },
              newsies_list.type
            )
          end
          true
        end
        tags = ["type:#{thread.class.name}", "success:#{success}", "code_path:#{code_path || "unknown"}"]
        GitHub.dogstats.increment("notifications.subscriptions.unsubscribe_from_thread.count", tags:)
        success
      end
    end

    # Delete thread subscriptions for provided user
    #
    # Returns true on success, false otherwise.
    def self.delete_thread_subscriptions(user_id:, thread_subscription_ids:)
      GitHub.tracer.in_span("delete_thread_subscriptions", kind: :internal) do
        success = GitHub.dogstats.distribution_time("notifications.subscriptions.delete_thread_subscriptions") do
          response = handle_errors(method: "delete_thread_subscriptions") do
            if FeatureFlag.vexi.enabled?(:notifyd_delete_thread_subscriptions, User.new(id: user_id), default: false)
              Notifyd::Subscriptions.schedule_delete_thread_subscriptions(user_id: user_id, thread_subscription_ids: thread_subscription_ids)
              GitHub.newsies.delete_thread_subscriptions(user_id: user_id, thread_subscription_ids: thread_subscription_ids)
            else
              GitHub.newsies.delete_thread_subscriptions(user_id: user_id, thread_subscription_ids: thread_subscription_ids)
            end
          end
          !!response&.success?
        end
        GitHub.dogstats.increment("notifications.subscriptions.delete_thread_subscriptions.count", tags: ["success:#{success}"])
        success
      end
    end

    # Subscribe a user to a repository.
    #
    # Returns true on success, false otherwise.
    sig { params(user: User, repository: Repository).returns(T::Boolean) }
    def self.subscribe_to_repository(user, repository)
      GitHub.tracer.in_span("subscribe_to_repository", kind: :internal) do
        success = GitHub.dogstats.distribution_time("notifications.subscriptions.subscribe_to_repository") do
          owner_id = repository.owner&.id
          return false if owner_id.nil?

          response = GitHub.newsies.subscribe_to_list(user, repository)
          return false unless response&.success?

          CalculateSubscribersCountByRepoJob.perform_later(repository)

          response = GitHub.dogstats.distribution_time("notifications.subscriptions.notifyd.subscribe_to_repository") do
            Notifyd::Subscriptions::NewsiesService.watch(
              user_id: user.id,
              repository_id: T.must(repository.id),
              owner_id: owner_id,
            )
          end
          GitHub.dogstats.increment("notifications.subscriptions.notifyd.subscribe_to_repository.count", tags: ["success:#{response}"])
          true
        end
        tags = ["success:#{success}"]
        GitHub.dogstats.increment("notifications.subscriptions.subscribe_to_repository.count", tags:)
        success
      end
    end

    # Subscribe a user to a set of thread types, or unsubscribe the user if the thread type set is empty.
    #
    # Returns true on success, false otherwise.
    sig { params(user: User, repository: Repository, thread_type_classes: T.nilable(T::Array[Class])).returns(T::Boolean) }
    def self.subscribe_to_thread_types(user, repository, thread_type_classes)
      GitHub.tracer.in_span("subscribe_to_thread_types", kind: :internal) do
        success = GitHub.dogstats.distribution_time("notifications.subscriptions.subscribe_to_thread_types") do
          owner_id = repository.owner&.id
          return false if owner_id.nil?

          response = GitHub.newsies.subscribe_to_thread_types(user, repository, thread_type_classes)
          return false unless response&.success?

          CalculateSubscribersCountByRepoJob.perform_later(repository)

          response = GitHub.dogstats.distribution_time("notifications.subscriptions.notifyd.subscribe_to_thread_types") do
            if thread_type_classes.nil? || thread_type_classes.empty?
              Notifyd::Subscriptions::NewsiesService.unwatch(user_id: user.id, repository_id: T.must(repository.id))
            else
              Notifyd::Subscriptions::NewsiesService.watch(
                user_id: user.id,
                repository_id: T.must(repository.id),
                owner_id: owner_id,
                thread_types: thread_type_classes.filter_map(&:name),
              )
            end
          end
          GitHub.dogstats.increment("notifications.subscriptions.notifyd.subscribe_to_thread_types.count", tags: ["success:#{response}"])
          true
        end
        tags = ["success:#{success}"]
        GitHub.dogstats.increment("notifications.subscriptions.subscribe_to_thread_types.count", tags:)
        success
      end
    end

    # Unsubscribe a user from a repository.
    #
    # Returns true on success, false otherwise.
    sig { params(user: User, repository: Repository).returns(T::Boolean) }
    def self.unsubscribe_from_repository(user, repository)
      GitHub.tracer.in_span("unsubscribe_from_repository", kind: :internal) do
        success = GitHub.dogstats.distribution_time("notifications.subscriptions.unsubscribe_from_repository") do
          response = GitHub.newsies.unsubscribe(user, repository)
          return false unless response&.success?

          CalculateSubscribersCountByRepoJob.perform_later(repository)

          response = GitHub.dogstats.distribution_time("notifications.subscriptions.notifyd.unsubscribe_from_repository") do
            Notifyd::Subscriptions::NewsiesService.unwatch(user_id: user.id, repository_id: T.must(repository.id))
          end
          GitHub.dogstats.increment("notifications.subscriptions.notifyd.unsubscribe_from_repository.count", tags: ["success:#{response}"])
          true
        end
        tags = ["success:#{success}"]
        GitHub.dogstats.increment("notifications.subscriptions.unsubscribe_from_repository.count", tags:)
        success
      end
    end

    # Mute a repo for a user.
    #
    # Returns true on success, false otherwise.
    sig { params(user: User, repository: Repository).returns(T::Boolean) }
    def self.mute_repository(user, repository)
      GitHub.tracer.in_span("mute_repository", kind: :internal) do
        success = GitHub.dogstats.distribution_time("notifications.subscriptions.mute_repository") do
          owner_id = repository.owner&.id
          return false if owner_id.nil?

          response = GitHub.newsies.ignore_list(user, repository)
          return false unless response&.success?

          CalculateSubscribersCountByRepoJob.perform_later(repository)

          response = GitHub.dogstats.distribution_time("notifications.subscriptions.notifyd.mute_repository") do
            Notifyd::Subscriptions::NewsiesService.ignore(
              user_id: user.id,
              repository_id: T.must(repository.id),
              owner_id: owner_id,
            )
          end
          GitHub.dogstats.increment("notifications.subscriptions.notifyd.mute_repository.count", tags: ["success:#{response}"])
          true
        end
        tags = ["success:#{success}"]
        GitHub.dogstats.increment("notifications.subscriptions.mute_repository.count", tags:)
        success
      end
    end

    # Asynchronously delete repository subscriptions of a specific type for a
    # user, optionally scoped to repositories owned by a specific owner.
    #
    # user_id           - An Integer user id.
    # owner_id          - An optional Integer owner (User) id.
    # subscription_type - A RepositorySubscriptionType enum value.
    #
    # Returns true on success, false otherwise.
    sig { params(user_id: Integer, owner_id: T.nilable(Integer), subscription_type: RepositorySubscriptionType).returns(T::Boolean) }
    def self.async_delete_user_repository_subscription_type(user_id:, owner_id:, subscription_type:)
      GitHub.tracer.in_span("async_delete_user_repository_subscription_type", kind: :internal) do
        success = GitHub.dogstats.distribution_time("notifications.subscriptions.async_delete_user_repository_subscription_type") do
          if GitHub.enterprise?
            if owner_id.nil?
              GitHub.newsies.async_delete_for_user_and_all_repositories(user_id, subscription_type.serialize)
              GitHub.dogstats.increment("newsies.async_unwatch_all_repositories.count", tags: ["type:#{subscription_type.serialize}"])
            else
              GitHub.newsies.async_delete_all_for_user_and_repository_owner(user_id, owner_id, subscription_type.serialize)
              GitHub.dogstats.increment("newsies.async_unwatch_all_for_owner.count", tags: ["type:#{subscription_type.serialize}"])
            end
          else
            Notifyd::MaintenanceService.new.delete_user_repository_subscription_type(user_id:, owner_id:, subscription_type:)
            GitHub.dogstats.increment("notifyd.async_delete_user_repository_subscription_type.count", tags: ["type:#{subscription_type.serialize}"])
          end

          true
        end
        GitHub.dogstats.increment("notifications.subscriptions.async_delete_user_repository_subscription_type.count", tags: ["success:#{success}"])
        success
      end
    end

    # Asynchronously delete all the subscriptions and settings for a single list.
    #
    # list - A list Subject (e.g. Repository, Team)
    #
    # Returns true on success, false otherwise.
    sig { params(list: Subject).returns(T::Boolean) }
    def self.async_delete_list_subscriptions(list)
      GitHub.tracer.in_span("async_delete_list_subscriptions", kind: :internal) do
        success = GitHub.dogstats.distribution_time("notifications.subscriptions.async_delete_list_subscriptions") do
          # NOTE(abeaumont): Newsies deletes both subscriptions and web notifications,
          # as both actions are coupled in the same job, breaking separation of concerns.
          GitHub.newsies.async_delete_all_for_list(Newsies::List.new(list.type, list.id))
          GitHub.dogstats.increment("newsies.async_delete_list_subscriptions.count")
          if list.type == "Repository" && !GitHub.enterprise?
            Notifyd::MaintenanceService.new.delete_repository(list.id)
            GitHub.dogstats.increment("notifyd.async_delete_list_subscriptions.count")
          end
          true
        end
        GitHub.dogstats.increment("notifications.subscriptions.async_delete_list_subscriptions.count", tags: ["success:#{success}"])
        success
      end
    end

    # Asynchronously delete list subscriptions for a sequence of users.
    #
    # list - A list Subject (e.g. Repository, Team)
    # user_ids - An array of integer user IDs.
    # restorable_id - Optional restorable ID for persistence recovery
    #
    # Returns true on success, false otherwise.
    sig { params(list: Subject, user_ids: T::Array[Integer], restorable_id: T.nilable(Integer)).returns(T::Boolean) }
    def self.async_delete_list_subscriptions_for_users(list:, user_ids:, restorable_id: nil)
      GitHub.tracer.in_span("async_delete_list_subscriptions_for_users", kind: :internal) do
        success = GitHub.dogstats.distribution_time("notifications.subscriptions.async_delete_list_subscriptions_for_users") do
          # NOTE(abeaumont): Newsies deletes both subscriptions and web notifications,
          # as both actions are coupled in the same job, breaking separation of concerns.
          GitHub.newsies.async_delete_all_for_list_and_users(Newsies::List.new(list.type, list.id), user_ids, restorable_id: restorable_id)
          GitHub.dogstats.count("newsies.async_delete_list_subscriptions_for_users.count", user_ids.length)
          if list.type == "Repository" && !GitHub.enterprise?
            Notifyd::MaintenanceService.new.delete_repository_for_users(repo_id: list.id, user_ids: user_ids)
            GitHub.dogstats.count("notifyd.async_delete_list_subscriptions_for_users.count", user_ids.length)
          end
          true
        end
        GitHub.dogstats.increment("notifications.subscriptions.async_delete_list_subscriptions_for_users.count", tags: ["success:#{success}"])
        success
      end
    end

    # Asynchronously delete all the subscriptions and settings for a user to a sequence of lists.
    #
    # user_id - A user identifier.
    # lists   - A sequence of Subjects of list type (e.g. Repository, Team)
    #
    # Returns true on success, false otherwise.
    sig { params(user_id: Integer, lists: T::Array[Subject]).returns(T::Boolean) }
    def self.async_delete_user_subscriptions_for_lists(user_id:, lists:)
      GitHub.tracer.in_span("async_delete_user_subscriptions_for_lists", kind: :internal) do
        success = GitHub.dogstats.distribution_time("notifications.subscriptions.async_delete_user_subscriptions_for_lists") do
          # NOTE(abeaumont): Newsies deletes both subscriptions and web notifications,
          # as both actions are coupled in the same job, breaking separation of concerns.
          newsies_lists = lists.map { |list| Newsies::List.new(list.type, list.id) }
          GitHub.newsies.async_delete_all_for_user_and_lists(user_id:, lists: newsies_lists)
          GitHub.dogstats.count("newsies.async_delete_user_subscriptions_for_lists.count", lists.length)
          repo_ids = lists.filter_map { |list| list.id if list.type == "Repository" }
          if !repo_ids.empty? && !GitHub.enterprise?
            Notifyd::MaintenanceService.new.delete_user_repositories(user_id: user_id, repo_ids: repo_ids)
            GitHub.dogstats.count("notifyd.async_delete_user_subscriptions_for_lists.count", repo_ids.length)
          end
          true
        end
        GitHub.dogstats.increment("notifications.subscriptions.async_delete_user_subscriptions_for_lists.count", tags: ["success:#{success}"])
        success
      end
    end

    # Delete all the subscriptions and settings for a user, asynchronously.
    #
    # Returns true on success, false otherwise.
    sig { params(user_id: Integer).returns(T::Boolean) }
    def self.async_delete_user_subscriptions(user_id)
      GitHub.tracer.in_span("async_delete_user_subscriptions", kind: :internal) do
        success = GitHub.dogstats.distribution_time("notifications.subscriptions.async_delete_user_subscriptions") do
          # NOTE(abeaumont): Newsies deletes both subscriptions and web notifications,
          # as both actions are coupled in the same job, breaking separation of concerns.
          GitHub.newsies.async_delete_all_for_user(user_id)
          GitHub.dogstats.increment("newsies.async_delete_user_subscriptions.count")
          if !GitHub.enterprise?
            Notifyd::MaintenanceService.new.delete_user(user_id)
            GitHub.dogstats.increment("notifyd.async_delete_user_subscriptions.count")
          end
          true
        end
        GitHub.dogstats.increment("notifications.subscriptions.async_delete_user_subscriptions.count", tags: ["success:#{success}"])
        success
      end
    end

    # Get a thread subscription status
    #
    # user    - A User.
    # List    - A list (ie: Repository).
    # thread  - A thread (ie: Issue, Commit, etc.).
    #
    # Returns the subscription status object on success, nil on failure.
    def self.thread_subscription_status(user, list, thread)
      GitHub.tracer.in_span("thread_subscription_status", kind: :internal) do
        response = GitHub.dogstats.distribution_time("notifications.subscriptions.thread_subscription_status") do
          if thread.respond_to?(:notifyd_primary?) && thread.notifyd_primary?(user)
            Notifyd::Subscriptions.subscription_status(user, list, thread)
          else
            GitHub.newsies.subscription_status(user, list, thread)
          end
        end
        result = response&.success? ? response.value : nil
        tags = ["success:#{!result.nil?}"]
        GitHub.dogstats.increment("notifications.subscriptions.thread_subscription_status.count", tags:)
        result
      end
    end

    # Get all subscribers to a thread, including those subscribed to the
    # thread in particular or to the list / thread type in general.
    #
    # This method should only be called as part of the Newsies notification
    # delivery pipeline.
    sig { params(list: Newsies::List, thread: Newsies::Thread).returns(T::Array[Newsies::Subscriber]) }
    def self.subscribers(list:, thread:)
      GitHub.tracer.in_span("subscribers", kind: :internal) do
        result = GitHub.dogstats.distribution_time("notifications.subscriptions.subscribers") do
          ignored = Set.new
          subscribed = {} # user_id => Subscriber

          handle = ->(subscriber) {
            if subscriber.ignored?
              ignored << subscriber.user_id
            else
              subscribed[subscriber.user_id] ||= subscriber
            end
          }

          Newsies::ThreadSubscription.each(thread) do |candidates|
            candidates.each(&handle)
          end

          Newsies::ThreadTypeSubscription.for_list(list).for_thread_type(thread.subscription_type).find_each do |subscription|
            handle.call(subscription.to_subscriber)
          end

          Newsies::ListSubscription.each(list) do |candidates|
            candidates.each(&handle)
          end

          ignored.each { |id| subscribed.delete(id) }
          subscribed.values
        end
        tags = ["success:#{!result.nil?}"]
        GitHub.dogstats.increment("notifications.subscriptions.subscribers.count", tags:)
        result
      end
    end

    # Get all the thread muters from a list of users. A muter is a user that
    # have a thread muted or the related reposiotry muted.
    #
    # This method should only be called as part of the Newsies notification
    # delivery pipeline.
    #
    # Returns an array of the of muter user IDs.
    sig do
      params(
        user_ids: T::Array[Integer],
        list: Newsies::List,
        thread: Newsies::Thread
      ).returns(T::Array[Integer])
    end
    def self.muters(user_ids, list:, thread:)
      GitHub.tracer.in_span("muters", kind: :internal) do
        result = GitHub.dogstats.distribution_time("notifications.subscriptions.muters") do
          muted = Set.new
          Newsies::ListSubscription.each(list) do |candidates|
            candidates.each do |sub|
              muted << sub.user_id if sub.ignored?
            end
          end

          Newsies::ThreadSubscription.each(thread) do |candidates|
            candidates.each do |sub|
              muted << sub.user_id if sub.ignored?
            end
          end
          (muted & user_ids.to_set).to_a
        end
        tags = ["success:#{!result.nil?}"]
        GitHub.dogstats.increment("notifications.subscriptions.muters.count", tags:)
        result
      end
    end

    # Gets the subscription status for a user and a list (e.g., Repository, Team, etc.).
    #
    # user - A User.
    # list - A list.
    #
    # Returns the subscription status object on success, nil on failure.
    sig { params(user: User, list: T.untyped).returns(T.nilable(Newsies::Subscription)) }
    def self.list_subscription_status(user, list)
      GitHub.tracer.in_span("list_subscription_status", kind: :internal) do
        response = GitHub.dogstats.distribution_time("notifications.subscriptions.list_subscription_status") do
          GitHub.newsies.subscription_status(user, list)
        end
        result = response&.success? ? response.value : nil
        tags = ["type:#{list.class.name}", "success:#{!result.nil?}"]
        GitHub.dogstats.increment("notifications.subscriptions.list_subscription_status.count", tags:)
        result
      end
    end

    # Returns true/false for a repository subscription on success, nil on failure.
    sig { params(user: User, repository: Repositories::IRepository).returns(T.nilable(T::Boolean)) }
    def self.repository_subscribed?(user, repository)
      GitHub.tracer.in_span("repository_subscribed", kind: :internal) do
        GitHub.dogstats.distribution_time("notifications.subscriptions.repository_subscribed") do
          response = GitHub.newsies.subscription_status(user, repository)

          result = response&.success? ? response.value.subscribed? : nil
          tags = ["result:#{result}"]
          GitHub.dogstats.increment("notifications.subscriptions.repository_subscribed.count", tags:)

          if notifyd_shadow_reads_enabled?(user)
            notifyd_result = GitHub.dogstats.distribution_time("notifications.subscriptions.notifyd.repository_subscribed") do
              Notifyd::Subscriptions::SubscriptionsService.repository_subscribed?(user.id, T.must(repository.id))
            end
            tags = ["result:#{notifyd_result}"]
            GitHub.dogstats.increment("notifications.subscriptions.notifyd.repository_subscribed.count", tags:)
            tags = ["matches:#{result == notifyd_result}"]
            GitHub.dogstats.increment("notifications.subscriptions.repository_subscribed.shadow.count", tags:)
          end

          result
        end
      end
    end

    # Returns true if a repository is muted, false otherwise
    sig { params(user: User, repository: Repositories::IRepository).returns(T::Boolean) }
    def self.repository_muted?(user, repository)
      GitHub.tracer.in_span("repository_muted", kind: :internal) do
        GitHub.dogstats.distribution_time("notifications.subscriptions.repository_muted") do
          result = Newsies::ListSubscription.status(user.id, Newsies::List.to_object(repository)).ignored?
          tags = ["result:#{result}"]
          GitHub.dogstats.increment("notifications.subscriptions.repository_muted.count", tags:)

          if notifyd_shadow_reads_enabled?(user)
            notifyd_result = GitHub.dogstats.distribution_time("notifications.subscriptions.notifyd.repository_muted") do
              Notifyd::Settings::RoutingSettingsService.repository_muted?(user.id, T.must(repository.id))
            end
            tags = ["result:#{notifyd_result}"]
            GitHub.dogstats.increment("notifications.subscriptions.notifyd.repository_muted.count", tags:)
            tags = ["matches:#{result == notifyd_result}"]
            GitHub.dogstats.increment("notifications.subscriptions.repository_muted.shadow.count", tags:)
          end

          result
        end
      end
    end

    # Returns subscribed repositories for a user, filtering out
    # inaccessible, deleted, or invisible repositories. Enqueues cleanup
    # jobs for any bad subscriptions found.
    #
    # user             - A User.
    # page             - An optional Integer for which page to return.
    # per_page         - An optional Integer for how many results to return per page.
    # excluding        - An optional Array of list_ids to be excluded on the MySQL side.
    # sort             - An optional String or Symbol direction to sort (:asc, "asc", :desc, "desc").
    #
    # Returns an Array of Repository instances on success, nil on failure.
    sig { params(user: User, page: T.nilable(Integer), per_page: T.nilable(Integer), excluding: T.nilable(T::Array[Integer]), sort: T.nilable(T.any(String, Symbol))).returns(T.untyped) }
    def self.subscribed_repositories(user, page: nil, per_page: nil, excluding: nil, sort: nil)
      GitHub.tracer.in_span("subscribed_repositories", kind: :internal) do
        response = GitHub.dogstats.distribution_time("notifications.subscriptions.subscribed_repositories") do
          GitHub.newsies.subscribed_repositories(user, set: :subscribed, page: page, per_page: per_page, excluding: excluding, sort: sort)
        end
        result = response&.success? ? response.value : nil
        tags = ["success:#{!result.nil?}"]
        GitHub.dogstats.increment("notifications.subscriptions.subscribed_repositories.count", tags:)
        result
      end
    end

    # Fetch list subscriptions for a user using cursor-based pagination.
    #
    # Wraps Newsies::ListSubscription.subscriptions_by_cursor to encapsulate
    # the Newsies model access within the notifications package.
    #
    # user_id          - An Integer user id.
    # excluding        - Optional Array of Newsies::List instances to exclude.
    # cursor           - Optional cursor value for pagination.
    # cursor_direction - Optional Symbol (:upwards or :downwards).
    # limit            - Optional Integer max results to return.
    #
    # Returns an Array of Newsies::ListSubscription::Subscription objects on success, nil on failure.
    def self.repository_subscriptions_by_cursor(user_id, excluding: nil, cursor: nil, cursor_direction: nil, limit: nil)
      GitHub.tracer.in_span("repository_subscriptions_by_cursor", kind: :internal) do
        options = {}
        options[:excluding] = excluding if excluding
        options[:cursor] = cursor if cursor
        options[:cursor_direction] = cursor_direction if cursor_direction
        options[:limit] = limit if limit
        response = GitHub.dogstats.distribution_time("notifications.subscriptions.repository_subscriptions_by_cursor") do
          Newsies::Responses::Array.new do
            Newsies::ListSubscription.subscriptions_by_cursor(user_id, options)
          end
        end
        result = response&.success? ? response.value : nil
        tags = ["success:#{!result.nil?}"]
        GitHub.dogstats.increment("notifications.subscriptions.repository_subscriptions_by_cursor.count", tags:)
        result
      end
    end

    # Fetch repository subscriptions for a user.
    #
    # Wraps Newsies::ListSubscription.subscriptions to encapsulate the Newsies
    # model access within the notifications package.
    #
    # user_id  - An Integer user id.
    # page     - Integer page number.
    # per_page - Integer items per page.
    #
    # Returns an Array of Notification::Subscription on success, nil on failure.
    sig { params(user_id: Integer, page: Integer, per_page: Integer).returns(T.untyped) }
    def self.repository_subscriptions(user_id, page:, per_page:)
      GitHub.tracer.in_span("repository_subscriptions", kind: :internal) do
        result = GitHub.dogstats.distribution_time("notifications.subscriptions.repository_subscriptions") do
          Newsies::ListSubscription.subscriptions(user_id, list_type: "Repository", set: :subscribed, page: page, per_page: per_page)
        end
        tags = ["success:#{!result.nil?}"]
        GitHub.dogstats.increment("notifications.subscriptions.repository_subscriptions.count", tags:)
        result
      end
    end

    # Fetch muted repositories for a user.
    #
    # Wraps Newsies::ListSubscription.subscriptions to encapsulate the Newsies
    # model access within the notifications package.
    #
    # user_id  - An Integer user id.
    # page     - Integer page number.
    # per_page - Integer items per page.
    #
    # Returns an Array of Notification::Subscription on success, nil on failure.
    sig { params(user_id: Integer, page: Integer, per_page: Integer).returns(T.untyped) }
    def self.repository_mutes(user_id, page:, per_page:)
      GitHub.tracer.in_span("repository_mutes", kind: :internal) do
        result = GitHub.dogstats.distribution_time("notifications.subscriptions.repository_mutes") do
          Newsies::ListSubscription.subscriptions(user_id, list_type: "Repository", set: :ignored, page: page, per_page: per_page)
        end
        tags = ["success:#{!result.nil?}"]
        GitHub.dogstats.increment("notifications.subscriptions.repository_mutes.count", tags:)
        result
      end
    end

    # Fetch a page of repository IDs the user is subscribed to.
    #
    # user_id - An Integer user id.
    #
    # Returns a page of Integer repository IDs on success, nil on failure.
    sig { params(user_id: Integer).returns(T.untyped) }
    def self.repository_subscription_ids(user_id)
      GitHub.tracer.in_span("repository_subscription_ids", kind: :internal) do
        result = GitHub.dogstats.distribution_time("notifications.subscriptions.repository_subscription_ids") do
          Newsies::ListSubscription.subscriptions_list_ids(user_id, list_type: "Repository", set: :subscribed)
        end
        tags = ["success:#{!result.nil?}"]
        GitHub.dogstats.increment("notifications.subscriptions.repository_subscription_ids.count", tags:)
        result
      end
    end

    # Fetch a page of repository IDs the user has muted.
    #
    # user_id - An Integer user id.
    # page    - Integer page number.
    #
    # Returns a page of Integer repository IDs on success, nil on failure.
    sig { params(user_id: Integer, page: Integer).returns(T.untyped) }
    def self.repository_mute_ids(user_id, page:)
      GitHub.tracer.in_span("repository_mute_ids", kind: :internal) do
        result = GitHub.dogstats.distribution_time("notifications.subscriptions.repository_mute_ids") do
          Newsies::ListSubscription.subscriptions_list_ids(user_id, list_type: "Repository", set: :ignored, page: page)
        end
        tags = ["success:#{!result.nil?}"]
        GitHub.dogstats.increment("notifications.subscriptions.repository_mute_ids.count", tags:)
        result
      end
    end

    # Fetch thread type subscriptions for a user.
    #
    # Wraps Newsies::ThreadTypeSubscription.subscriptions to encapsulate the
    # Newsies model access within the notifications package.
    #
    # user_id  - An Integer user id.
    # page     - Integer page number.
    # per_page - Integer items per page.
    #
    # Returns an Array of Notification::Subscription on success, nil on failure.
    sig { params(user_id: Integer, page: Integer, per_page: Integer).returns(T.untyped) }
    def self.thread_type_subscriptions(user_id, page:, per_page:)
      GitHub.tracer.in_span("thread_type_subscriptions", kind: :internal) do
        result = GitHub.dogstats.distribution_time("notifications.subscriptions.thread_type_subscriptions") do
          Newsies::ThreadTypeSubscription.subscriptions(user_id, page: page, per_page: per_page, list_type: "Repository")
        end
        tags = ["success:#{!result.nil?}"]
        GitHub.dogstats.increment("notifications.subscriptions.thread_type_subscriptions.count", tags:)
        result
      end
    end

    # Fetch repository IDs for a user's thread type subscriptions.
    #
    # Wraps Newsies::ThreadTypeSubscription.subscriptions_list_ids.
    #
    # user_id - An Integer user id.
    # page    - Integer page number.
    #
    # Returns a page of Integer repository IDs on success, nil on failure.
    sig { params(user_id: Integer, page: Integer).returns(T.untyped) }
    def self.thread_type_subscription_ids(user_id, page:)
      GitHub.tracer.in_span("thread_type_subscription_ids", kind: :internal) do
        result = GitHub.dogstats.distribution_time("notifications.subscriptions.thread_type_subscription_ids") do
          Newsies::ThreadTypeSubscription.subscriptions_list_ids(user_id, page: page, list_type: "Repository")
        end
        tags = ["success:#{!result.nil?}"]
        GitHub.dogstats.increment("notifications.subscriptions.thread_type_subscription_ids.count", tags:)
        result
      end
    end

    # Get the list subscriptions for the given user and repository IDs.
    #
    # Returns the subscriptions array on success, nil on failure.
    sig { params(user_id: Integer, repository_ids: T::Array[Integer]).returns(T.untyped) }
    def self.user_repository_subscriptions(user_id, repository_ids)
      GitHub.tracer.in_span("user_repository_subscriptions", kind: :internal) do
        response = GitHub.dogstats.distribution_time("notifications.subscriptions.user_repository_subscriptions") do
          lists = repository_ids.map { |id| Newsies::List.new("Repository", id) }
          GitHub.newsies.user_list_subscriptions(user_id, lists)
        end
        result = response&.success? ? response.value : nil
        tags = ["success:#{!result.nil?}"]
        GitHub.dogstats.increment("notifications.subscriptions.user_repository_subscriptions.count", tags:)
        result
      end
    end

    # Get the thread type subscriptions for the given user and threads.
    #
    # Wraps GitHub.newsies.user_thread_type_subscriptions to encapsulate the
    # Newsies service access within the notifications package.
    #
    # user_id - An Integer user id.
    # threads - An Array of Newsies::Thread instances to scope to.
    #
    # Returns the subscriptions array on success, nil on failure.
    def self.user_thread_type_subscriptions(user_id, threads)
      GitHub.tracer.in_span("user_thread_type_subscriptions", kind: :internal) do
        response = GitHub.dogstats.distribution_time("notifications.subscriptions.user_thread_type_subscriptions") do
          GitHub.newsies.user_thread_type_subscriptions(user_id, threads)
        end
        result = response&.success? ? response.value : nil
        tags = ["success:#{!result.nil?}"]
        GitHub.dogstats.increment("notifications.subscriptions.user_thread_type_subscriptions.count", tags:)
        result
      end
    end

    # Count a user's repository subscriptions.
    #
    # Wraps Newsies::ListSubscription.count_subscriptions.
    #
    # user_id   - An Integer user id.
    # excluding - Optional Array of repository ids to exclude.
    #
    # Returns an Integer count on success, nil on failure.
    sig { params(user_id: Integer, excluding: T.nilable(T::Array[Integer])).returns(T.nilable(Integer)) }
    def self.count_repository_subscriptions(user_id, excluding: nil)
      GitHub.tracer.in_span("count_repository_subscriptions", kind: :internal) do
        excluding_lists = excluding&.map { |id| Newsies::List.new("Repository", id) }
        result = GitHub.dogstats.distribution_time("notifications.subscriptions.count_repository_subscriptions") do
          Newsies::ListSubscription.count_subscriptions(user_id, set: :subscribed, excluding: excluding_lists, list_type: "Repository")
        end
        tags = ["success:#{!result.nil?}"]
        GitHub.dogstats.increment("notifications.subscriptions.count_repository_subscriptions.count", tags:)
        result
      end
    end

    # Count a user's muted repositories.
    #
    # Wraps Newsies::ListSubscription.count_subscriptions.
    #
    # user_id   - An Integer user id.
    #
    # Returns an Integer count on success, nil on failure.
    sig { params(user_id: Integer).returns(T.nilable(Integer)) }
    def self.count_repository_mutes(user_id)
      GitHub.tracer.in_span("count_repository_mutes", kind: :internal) do
        result = GitHub.dogstats.distribution_time("notifications.subscriptions.count_repository_mutes") do
          Newsies::ListSubscription.count_subscriptions(user_id, set: :ignored, list_type: "Repository")
        end
        tags = ["success:#{!result.nil?}"]
        GitHub.dogstats.increment("notifications.subscriptions.count_repository_mutes.count", tags:)
        result
      end
    end

    # Count a user's thread type subscriptions.
    #
    # Wraps Newsies::ThreadTypeSubscription.count_subscriptions.
    #
    # user_id - An Integer user id.
    #
    # Returns an Integer count on success, nil on failure.
    sig { params(user_id: Integer).returns(T.nilable(Integer)) }
    def self.count_thread_type_subscriptions(user_id)
      GitHub.tracer.in_span("count_thread_type_subscriptions", kind: :internal) do
        result = GitHub.dogstats.distribution_time("notifications.subscriptions.count_thread_type_subscriptions") do
          Newsies::ThreadTypeSubscription.count_subscriptions(user_id, list_type: "Repository")
        end
        tags = ["success:#{!result.nil?}"]
        GitHub.dogstats.increment("notifications.subscriptions.count_thread_type_subscriptions.count", tags:)
        result
      end
    end

    # Returns all user IDs subscribed to a repository
    sig { params(repository_id: Integer).returns(T::Array[Integer]) }
    def self.all_repository_subscribers(repository_id)
      GitHub.tracer.in_span("all_repository_subscribers", kind: :internal) do
        result = GitHub.dogstats.distribution_time("notifications.subscriptions.all_repository_subscribers") do
          list = Newsies::List.new("Repository", repository_id)
          Newsies::ListSubscription.for_list(list).excluding_ignored.distinct.pluck(:user_id)
        end
        tags = ["success:#{!result.nil?}"]
        GitHub.dogstats.increment("notifications.subscriptions.all_repository_subscribers.count", tags:)
        result
      end
    end

    # Return all user IDs muting a repository.
    sig { params(repository_id: Integer).returns(T::Array[Integer]) }
    def self.all_repository_muters(repository_id)
      GitHub.tracer.in_span("all_repository_muters", kind: :internal) do
        result = GitHub.dogstats.distribution_time("notifications.subscriptions.all_repository_muters") do
          list = Newsies::List.new("Repository", repository_id)
          Newsies::ListSubscription.for_list(list).only_ignored.distinct.pluck(:user_id)
        end
        tags = ["success:#{!result.nil?}"]
        GitHub.dogstats.increment("notifications.subscriptions.all_repository_muters.count", tags:)
        result
      end
    end

    # List subscribers for a repository, paginated.
    #
    # Spammy users are always excluded.
    #
    # repository - A Repository.
    # page       - Integer page number.
    # per_page   - Integer number of results per page.
    #
    # Returns an Array of subscribers on success, nil on failure.
    sig do
      params(
        repository: Repository,
        page: Integer,
        per_page: Integer
      ).returns(T.nilable(T::Array[T.untyped]))
    end
    def self.repository_subscribers_by_page(repository, page:, per_page:)
      GitHub.tracer.in_span("repository_subscribers_by_page", kind: :internal) do
        response = GitHub.dogstats.distribution_time("notifications.subscriptions.repository_subscribers_by_page") do
          GitHub.newsies.subscribers(repository, page: page, per_page: per_page, exclude_spammy_users: true)
        end
        result = response&.success? ? response.value : nil
        tags = ["success:#{!result.nil?}"]
        GitHub.dogstats.increment("notifications.subscriptions.repository_subscribers_by_page.count", tags:)
        result
      end
    end

    # Get subscriber IDs for a list using cursor-based pagination.
    #
    # list              - A list (e.g. Repository).
    # cursor            - Optional Integer cursor position (user ID).
    # cursor_direction  - Optional Symbol direction (:upwards or :downwards).
    # limit             - Optional Integer max number of results.
    # exclude_spammy_users - Optional Boolean to exclude spammy users.
    #
    # Returns an Array of Integer user IDs on success, nil on failure.
    sig do
      params(
        repository: Repositories::IRepository,
        cursor: T.nilable(T.any(Integer, String)),
        cursor_direction: T.nilable(Symbol),
        limit: T.nilable(Integer),
        exclude_spammy_users: T.nilable(T::Boolean),
      ).returns(T.nilable(T::Array[Integer]))
    end
    def self.repository_subscriber_ids_by_cursor(repository, cursor: nil, cursor_direction: nil, limit: nil, exclude_spammy_users: nil)
      GitHub.tracer.in_span("repository_subscriber_ids_by_cursor", kind: :internal) do
        options = {}
        options[:cursor] = cursor if cursor
        options[:cursor_direction] = cursor_direction if cursor_direction
        options[:limit] = limit if limit
        options[:exclude_spammy_users] = exclude_spammy_users unless exclude_spammy_users.nil?

        response = GitHub.dogstats.distribution_time("notifications.subscriptions.repository_subscriber_ids_by_cursor") do
          GitHub.newsies.subscriber_ids_by_cursor(repository, options)
        end
        result = response&.success? ? response.value : nil
        tags = ["success:#{!result.nil?}"]
        GitHub.dogstats.increment("notifications.subscriptions.repository_subscriber_ids_by_cursor.count", tags:)
        result
      end
    end

    # Fetch unique subscriber user IDs for a repository across all subscription types.
    #
    # Queries all three tables with the same cursor, merges, deduplicates,
    # and returns the first `limit` user IDs.
    #
    # repository_id - Integer repository ID.
    # after         - Integer cursor (user_id). Returns users with user_id > after.
    # limit         - Integer max number of user IDs to return per batch.
    #
    # Returns Array<Integer> of user IDs, sorted ascending, deduplicated.
    sig { params(repository_id: Integer, after: Integer, limit: Integer).returns(T::Array[Integer]) }
    def self.all_repository_subscriber_ids(repository_id, after: 0, limit: 1000)
      GitHub.tracer.in_span("all_repository_subscriber_ids", kind: :internal) do
        result = GitHub.dogstats.distribution_time("notifications.subscriptions.all_repository_subscriber_ids") do
          list = Newsies::List.new("Repository", repository_id)
          ids = Newsies::ThreadSubscription.for_list(list)
            .where("user_id > ?", after).order(user_id: :asc)
            .limit(limit).distinct.pluck(:user_id)
          ids += Newsies::ListSubscription.for_list(list)
            .where("user_id > ?", after).order(user_id: :asc)
            .limit(limit).distinct.pluck(:user_id)
          ids += Newsies::ThreadTypeSubscription.for_list(list)
            .where("user_id > ?", after).order(user_id: :asc)
            .limit(limit).distinct.pluck(:user_id)
          ids.uniq.sort.first(limit)
        end
        tags = ["success:#{!result.nil?}"]
        GitHub.dogstats.increment("notifications.subscriptions.all_repository_subscriber_ids.count", tags:)
        result
      end
    end

    # Checks the subscription status for an array of users against a repository.
    #
    # users      - An Array of Users.
    # repository - A Repository.
    #
    # Returns an Array of Subscription objects on success, nil on failure.
    sig { params(users: T::Array[User], repository: Repositories::IRepository).returns(T.nilable(T::Array[T.untyped])) }
    def self.repository_subscriptions_status(users, repository)
      GitHub.tracer.in_span("repository_subscriptions_status", kind: :internal) do
        response = GitHub.dogstats.distribution_time("notifications.subscriptions.repository_subscriptions_status") do
          GitHub.newsies.subscription_status_all(users, repository)
        end
        result = response&.success? ? response.value : nil
        tags = ["success:#{!result.nil?}"]
        GitHub.dogstats.increment("notifications.subscriptions.repository_subscriptions_status.count", tags:)
        result
      end
    end

    # Checks which users have muted a repository.
    #
    # user_ids      - An Array of user IDs.
    # repository_id - Integer repository ID.
    #
    # Returns an Array of muted user IDs on success, nil on failure.
    sig { params(user_ids: T::Array[Integer], repository_id: Integer).returns(T.nilable(T::Array[Integer])) }
    def self.repository_muters(user_ids, repository_id)
      GitHub.tracer.in_span("repository_muters", kind: :internal) do
        GitHub.dogstats.distribution_time("notifications.subscriptions.repository_muters") do
          next [] if user_ids.empty?

          list = Newsies::List.new("Repository", repository_id)
          result = begin
            Newsies::ListSubscription.for_list(list).only_ignored.where(user_id: user_ids).distinct.pluck(:user_id)
          rescue ActiveRecord::ActiveRecordError => e
            Failbot.report(e)
            nil
          end

          tags = ["success:#{!result.nil?}"]
          GitHub.dogstats.increment("notifications.subscriptions.repository_muters.count", tags:)

          if notifyd_shadow_reads_enabled?(User.new(id: user_ids.first))
            notifyd_result = GitHub.dogstats.distribution_time("notifications.subscriptions.notifyd.repository_muters") do
              Notifyd::Settings::RoutingSettingsService.repository_muters(user_ids, repository_id)
            end
            tags = ["success:#{!notifyd_result.nil?}"]
            GitHub.dogstats.increment("notifications.subscriptions.notifyd.repository_muters.count", tags:)
            matches = !result.nil? && !notifyd_result.nil? && result.sort == notifyd_result.sort
            tags = ["matches:#{matches}"]
            GitHub.dogstats.increment("notifications.subscriptions.repository_muters.shadow.count", tags:)
          end

          result
        end
      end
    end

    # Count subscribers for a repository.
    #
    # repository_id      - Integer repository ID.
    # exclude_spammy_users - Boolean whether to exclude spammy users.
    #
    # Returns an Integer count on success, nil on failure.
    sig { params(repository_id: Integer, exclude_spammy_users: T::Boolean).returns(T.nilable(Integer)) }
    def self.count_repository_subscribers(repository_id, exclude_spammy_users:)
      GitHub.tracer.in_span("count_repository_subscribers", kind: :internal) do
        response = GitHub.dogstats.distribution_time("notifications.subscriptions.count_repository_subscribers") do
          list = Newsies::List.new("Repository", repository_id)
          GitHub.newsies.count_subscribers(list, exclude_spammy_users: exclude_spammy_users)
        end
        result = response&.success? ? response.value : nil
        tags = ["success:#{!result.nil?}", "exclude_spammy:#{exclude_spammy_users}"]
        GitHub.dogstats.increment("notifications.subscriptions.count_repository_subscribers.count", tags:)
        result
      end
    end

    # Public: Count subscriber user IDs for a repository across all subscription types.
    #
    # Returns the sum of per-type unique subscriber counts. This is an upper
    # bound — users subscribed via multiple types are counted multiple times.
    sig { params(repository_id: Integer).returns(Integer) }
    def self.count_all_repository_subscribers(repository_id)
      GitHub.tracer.in_span("count_all_repository_subscribers", kind: :internal) do
        result = GitHub.dogstats.distribution_time("notifications.subscriptions.count_all_repository_subscribers") do
          list = Newsies::List.new("Repository", repository_id)

          Newsies::ListSubscription.for_list(list).distinct.count(:user_id) +
            Newsies::ThreadTypeSubscription.for_list(list).distinct.count(:user_id) +
            Newsies::ThreadSubscription.for_list(list).distinct.count(:user_id)
        end
        tags = ["success:#{!result.nil?}"]
        GitHub.dogstats.increment("notifications.subscriptions.count_all_repository_subscribers.count", tags:)
        result
      end
    end

    # Public: Get a reason string from any valid reason type
    #
    # reason  - Optional String, Symbol or Hash reason
    #           (ie: "mention", :mention, {:reason => :mention, :force => true}).
    #
    # Returns a String reason on success, nil on failure.
    def self.valid_reason_from(reason)
      options = Newsies::ThreadSubscribeOptions.from(reason)
      Newsies::Reasons.valid_reason_from(options.reason).to_s
    end

    # Public: Checks if a user has exceeded the maximum number of repository
    # subscriptions.
    #
    # user - A User.
    #
    # Returns true if the limit is exceeded, false if not, nil on error.
    sig { params(user: User).returns(T.nilable(T::Boolean)) }
    def self.repository_subscription_limit_exceeded?(user)
      GitHub.tracer.in_span("repository_subscription_limit_exceeded", kind: :internal) do
        result = GitHub.dogstats.distribution_time("notifications.subscriptions.repository_subscription_limit_exceeded") do
          next false if GitHub.enterprise?
          next false unless FeatureFlag.vexi.enabled?(:enable_notifications_repository_subscription_limits, user, default: false)
          next false if FeatureFlag.vexi.enabled?(:enable_notifications_repository_subscription_limits_override, user, default: false)

          count = count_repository_subscriptions(user.id)
          next nil if count.nil?

          if count >= Newsies::Service::MAX_REPOSITORY_SUBSCRIPTIONS_PER_USER
            GitHub.dogstats.count("api.notifications.subscription_limit_exceeded", 1)
            next true
          end
          next false
        end
        GitHub.dogstats.increment("notifications.subscriptions.repository_subscription_limit_exceeded.count", tags: ["result:#{result}"])
        result
      end
    end

    private

    # Whether shadow reads are enabled.
    sig { params(user: User).returns(T::Boolean) }
    private_class_method def self.notifyd_shadow_reads_enabled?(user)
      FeatureFlag.vexi.enabled?(:notifyd_enable_shadow_repository_subscription_reads, user, default: false)
    end

    private_class_method def self.handle_errors(raise_errors: false, type: :newsies, method:, &block)
      begin
        yield
      rescue => e
        GitHub.dogstats.increment(EXCEPTIONS_STAT, tags: ["system:#{type}"])
        NotificationsFailbot.report(e, "service.name": type.to_s, "code.function": method)
        raise e if raise_errors
        nil
      end
    end
  end
end
