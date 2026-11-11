# typed: true
# frozen_string_literal: true

module Notifications
  module Subscriptions
    extend Notifyd::Subscriptions

    EXCEPTIONS_STAT = "notifications.subscriptions.exceptions"
    DIFFERENCE_STAT = "notifications.subscriptions.differences"

    # Public: Subscribe a user to a thread.
    #
    # user    - A User.
    # list    - A list (ie: Repository).
    # thread  - A thread (ie: Issue, Commit, etc.).
    # reason  - Optional String, Symbol or Hash reason
    #           (ie: "mention", :mention, {:reason => :mention, :force => true}).
    # events  - Optional Array of String event names
    #
    # Returns Newsies::Responses::Boolean.
    def self.subscribe_to_thread(user, list, thread, reason = nil, events = [])
      GitHub.tracer.in_span("subscribe_to_thread", kind: :internal) do
        reason_for_notifyd = valid_reason_from(reason)
        send_to_notifyd = thread&.respond_to?(:subscribe_in_notifyd?) && thread&.subscribe_in_notifyd?(user, reason_for_notifyd)
        notifyd_primary = thread&.respond_to?(:notifyd_primary?) && thread.notifyd_primary?(user)

        newsies_response = handle_errors(raise_errors: !notifyd_primary, response_class: Newsies::Responses::Boolean, method: "subscribe_to_thread") do
          GitHub.newsies.subscribe_to_thread(user, list, thread, reason, events)
        end

        return newsies_response unless send_to_notifyd

        notifyd_response = handle_errors(response_class: Notifyd::Responses::Boolean, method: "subscribe_to_thread") do
          notifyd_subscribe_to_thread(user, list, thread, reason_for_notifyd)
        end

        if notifyd_response&.value != newsies_response&.value
          GitHub.dogstats.increment(DIFFERENCE_STAT, tags: ["method:subscribe_to_thread"])
          GitHub.logger.info("found differences in results between notifyd and newsies", {
            "code.namespace" => "Notifications::Subscriptions",
            "code.function" => "subscribe_to_thread",
            "gh.notifications.response" => newsies_response.nil? ? "" : newsies_response,
            "gh.notifyd.response" => notifyd_response.nil? ? "" : notifyd_response
          })
        end
        notifyd_primary ? notifyd_response : newsies_response
      end
    end

    # Public: Unsubscribe a user from a thread.
    #
    # user    - A User.
    # thread  - A thread (ie: Issue, Commit, etc.).
    #
    # Returns true on success, false otherwise.
    def self.unsubscribe_from_thread(user, thread)
      GitHub.tracer.in_span("unsubscribe_from_thread", kind: :internal) do
        success = GitHub.dogstats.distribution_time("notifications.subscriptions.unsubscribe_from_thread") do
          notifyd_primary = thread&.respond_to?(:notifyd_primary?) && thread.notifyd_primary?(user)

          newsies_list = Newsies::List.to_object(thread.notifications_list)
          newsies_thread = Newsies::Thread.to_object(thread.notifications_thread, list: newsies_list)

          newsies_response = handle_errors(raise_errors: !notifyd_primary, response_class: Newsies::Response, method: "unsubscribe_from_thread") do
            Newsies::Response.new do
              # If the user is subscribed to the list, then we must insert an "ignoring" thread
              # subscription to block notifications that would otherwise be sent to the list.
              #
              # If the user is ignoring the list, we fall through and delete the thread subscription
              # at the end.
              if Newsies::ListSubscription.for_user(user.id).for_list(newsies_list).excluding_ignored.exists?
                Newsies::ThreadSubscription.ignore(user.id, newsies_thread)

              # If the user is subscribed to the thread type, then we must insert
              # an "ignoring" record for the thread to block notifications that
              # would otherwise be sent due to the thread type subscription
              elsif Newsies::ThreadTypeSubscription.for_user(user.id).for_list(newsies_list).for_thread_type(newsies_thread.subscription_type).exists?
                Newsies::ThreadSubscription.ignore(user.id, newsies_thread)

              # The user has no list-level subscriptions, so to unsubscribe from
              # future notifications on this thread (until they are re-subscribed)
              # we can simply delete the thread subscription
              else
                Newsies::ThreadSubscription.for_user(user.id).for_thread(newsies_thread).destroy_all
              end
            end
          end

          return false unless newsies_response&.success?

          if thread&.respond_to?(:unsubscribe_in_notifyd?) && thread&.unsubscribe_in_notifyd?(user)
            notifyd_response = handle_errors(response_class: Notifyd::Responses::Boolean, method: "unsubscribe_from_thread") do
              notifyd_unsubscribe_from_thread(user, thread)
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
        tags = ["type:#{thread.class.name}", "success:#{success}"]
        GitHub.dogstats.increment("notifications.subscriptions.unsubscribe_from_thread.count", tags:)
        success
      end
    end

    # Public: Processes various subscription update actions
    #
    # subscribable - A thread object (e.g. Issue / PullRequest)
    # state - the desired end state for the subscription
    # user - the user who is performing the action
    # types - optional. thread types to subscribe to
    def self.process_subscription_update(subscribable:, state:, user:, types: [], events: [])
      if subscribable.is_a?(::PullRequest)
        subscribable = subscribable.issue
      end

      case subscribable
      when ::Repository
        case state
        when "custom"
          if types.present?
            user.subscribe_to_thread_types(subscribable, types.map(&:constantize))
          else
            raise ArgumentError.new("Types input field cannot be empty with custom subscription.")
          end
        when "unsubscribed"
          user.unwatch_repo(subscribable)
        when "subscribed"
          raise ArgumentError.new("Unable to subscribe") unless user.watch_repo(subscribable)
        when "ignored"
          user.ignore_repo(subscribable)
        when "releases_only"
          user.subscribe_to_thread_types(subscribable, [::Release])
        end
      when ::Commit
        case state
        when "unsubscribed", "ignored"
          unsubscribe_from_thread(user, subscribable)
        when "subscribed"
          subscribe_to_thread(user, subscribable.notifications_list, subscribable, :manual)
        end
      when ::Issue, ::PullRequest, ::Discussion
        case state
        when "unsubscribed", "ignored"
          subscribable.unsubscribe(user) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
        when "subscribed"
          subscribable.subscribe(user, :manual)
        when "custom"
          subscribable.subscribe(user, :manual, events)
        end
      end
    end

    # Public: Get a subscription status
    #
    # user    - A User.
    # List    - A list (ie: Repository).
    # thread  - A thread (ie: Issue, Commit, etc.).
    #
    # Returns Newsies::Response or Notifyd::Response
    def self.thread_subscription_status(user, list, thread)
      GitHub.tracer.in_span("thread_subscription_status", kind: :internal) do
        if thread.respond_to?(:notifyd_primary?) && thread.notifyd_primary?(user)
          notifyd_subscription_status(user, list, thread)
        else
          GitHub.newsies.subscription_status(user, list, thread)
        end
      end
    end

    # Public: Gets the subscription status for a user and a list (e.g., Repository, Team, etc.).
    #
    # user - A User.
    # list - A list.
    #
    # Returns Newsies::Responses::Subscription.
    def self.list_subscription_status(user, list)
      GitHub.tracer.in_span("list_subscription_status", kind: :internal) do
        GitHub.dogstats.distribution_time("notifications.subscriptions.list_subscription_status") do
          response = GitHub.newsies.subscription_status(user, list)
          tags = ["type:#{list.class.name}", "success:#{response.success?}"]
          GitHub.dogstats.increment("notifications.subscriptions.list_subscription_status.count", tags:)
          response
        end
      end
    end

    # Public: Returns true if a list subscription is ignored, false otherwise
    #
    # user - A User.
    # list - A list.
    def self.list_ignored?(user, list)
      GitHub.tracer.in_span("list_ignored", kind: :internal) do
        GitHub.dogstats.distribution_time("notifications.subscriptions.list_ignored") do
          newsies_list = Newsies::List.to_object(list)
          response = Newsies::ListSubscription.status(user.id, newsies_list).ignored?
          tags = ["type:#{list.class.name}"]
          GitHub.dogstats.increment("notifications.subscriptions.list_ignored.count", tags:)
          response
        end
      end
    end

    # Public: Checks the subscription status for an array of users against a repository.
    #
    # users      - An Array of Users.
    # repository - A Repository.
    #
    # Returns Newsies::Responses::Array wrapping an array of Subscription objects.
    sig { params(users: T::Array[User], repository: Repository).returns(Newsies::Responses::Array) }
    def self.repository_subscriptions_status(users, repository)
      GitHub.tracer.in_span("repository_subscriptions_status", kind: :internal) do
        response = GitHub.dogstats.distribution_time("notifications.subscriptions.repository_subscriptions_status") do
          GitHub.newsies.subscription_status_all(users, repository)
        end
        tags = ["success:#{response.success?}"]
        GitHub.dogstats.increment("notifications.subscriptions.repository_subscriptions_status.count", tags:)
        response
      end
    end

    # Subscribe a user to a repository.
    #
    # Returns true on success, false otherwise.
    sig { params(user: User, repository: Repositories::IRepository).returns(T::Boolean) }
    def self.subscribe_to_repository(user, repository)
      GitHub.tracer.in_span("subscribe_to_repository", kind: :internal) do
        success = GitHub.dogstats.distribution_time("notifications.subscriptions.subscribe_to_repository") do
          response = GitHub.newsies.subscribe_to_list(user, repository)
          return false unless response.success?

          if notifyd_sync_repository_list?(user, repository)
            Notifyd::NewsiesService.new.watch(user: user, list: repository)
          end
          true
        end
        tags = ["type:#{repository.class.name}", "success:#{success}"]
        GitHub.dogstats.increment("notifications.subscriptions.subscribe_to_repository.count", tags:)
        success
      end
    end

    # Subscribe a user to a set of thread types, or unsubscribe the user if the thread type set is empty.
    #
    # Returns true on success, false otherwise.
    sig { params(user: User, repository: Repositories::IRepository, thread_type_classes: T.nilable(T::Array[Class])).returns(T::Boolean) }
    def self.subscribe_to_thread_types(user, repository, thread_type_classes)
      GitHub.tracer.in_span("subscribe_to_thread_types", kind: :internal) do
        success = GitHub.dogstats.distribution_time("notifications.subscriptions.subscribe_to_thread_types") do
          response = GitHub.newsies.subscribe_to_thread_types(user, repository, thread_type_classes)
          return false unless response.success?
          if notifyd_sync_repository_list?(user, repository)
            if thread_type_classes.nil? || thread_type_classes.empty?
              Notifyd::NewsiesService.new.unwatch(user: user, lists: [repository])
            else
              Notifyd::NewsiesService.new.watch(user: user, list: repository, thread_types: thread_type_classes.map(&:name))
            end
          end
          true
        end
        tags = ["type:#{repository.class.name}", "success:#{success}"]
        GitHub.dogstats.increment("notifications.subscriptions.subscribe_to_thread_types.count", tags:)
        success
      end
    end

    # Unsubscribe a user from a repository.
    #
    # Returns true on success, false otherwise.
    sig { params(user: User, repository: Repositories::IRepository).returns(T::Boolean) }
    def self.unsubscribe_from_repository(user, repository)
      GitHub.tracer.in_span("unsubscribe_from_repository", kind: :internal) do
        success = GitHub.dogstats.distribution_time("notifications.subscriptions.unsubscribe_from_repository") do
          response = GitHub.newsies.unsubscribe(user, repository)
          return false unless response.success?
          if notifyd_sync_repository_list?(user, repository)
            Notifyd::NewsiesService.new.unwatch(user: user, lists: [repository])
          end
          true
        end
        tags = ["type:#{repository.class.name}", "success:#{success}"]
        GitHub.dogstats.increment("notifications.subscriptions.unsubscribe_from_repository.count", tags:)
        success
      end
    end

    # Mute a repo for a user.
    #
    # Returns true on success, false otherwise.
    sig { params(user: User, repository: Repositories::IRepository).returns(T::Boolean) }
    def self.mute_repository(user, repository)
      GitHub.tracer.in_span("mute_repository", kind: :internal) do
        success = GitHub.dogstats.distribution_time("notifications.subscriptions.mute_repository") do
          response = GitHub.newsies.ignore_list(user, repository)
          return false unless response.success?
          if notifyd_sync_repository_list?(user, repository)
            Notifyd::NewsiesService.new.ignore(user: user, list: repository)
          end
          true
        end
        tags = ["type:#{repository.class.name}", "success:#{success}"]
        GitHub.dogstats.increment("notifications.subscriptions.mute_repository.count", tags:)
        success
      end
    end

    # Public: List subscribers for a repository, paginated.
    #
    # Spammy users are always excluded.
    #
    # repository - A Repository.
    # page       - Integer page number.
    # per_page   - Integer number of results per page.
    #
    # Returns a Newsies::Responses::Array instance.
    sig do
      params(
        repository: Repository,
        page: Integer,
        per_page: Integer
      ).returns(Newsies::Responses::Array)
    end
    def self.repository_subscribers_by_page(repository, page:, per_page:)
      GitHub.tracer.in_span("repository_subscribers_by_page", kind: :internal) do
        GitHub.dogstats.distribution_time("notifications.subscriptions.repository_subscribers_by_page") do
          response = GitHub.newsies.subscribers(repository, page: page, per_page: per_page, exclude_spammy_users: true)
          tags = ["success:#{response.success?}"]
          GitHub.dogstats.increment("notifications.subscriptions.repository_subscribers_by_page.count", tags:)
          response
        end
      end
    end

    # Public: Count subscribers for a repository.
    #
    # repository         - A Repository.
    # exclude_spammy_users - Boolean whether to exclude spammy users.
    #
    # Returns a Newsies::Responses::Count instance.
    sig { params(repository: Repository, exclude_spammy_users: T::Boolean).returns(Newsies::Responses::Count) }
    def self.count_repository_subscribers(repository, exclude_spammy_users:)
      GitHub.tracer.in_span("count_repository_subscribers", kind: :internal) do
        GitHub.dogstats.distribution_time("notifications.subscriptions.count_repository_subscribers") do
          response = GitHub.newsies.count_subscribers(repository, exclude_spammy_users: exclude_spammy_users)
          tags = ["success:#{!response.failed?}", "exclude_spammy:#{exclude_spammy_users}"]
          GitHub.dogstats.increment("notifications.subscriptions.count_repository_subscribers.count", tags:)
          response
        end
      end
    end

    # Returns all user IDs subscribed to a repository
    sig { params(repository_id: Integer).returns(T::Array[Integer]) }
    def self.repository_subscribers(repository_id)
      list = Newsies::List.new("Repository", repository_id)
      Newsies::ListSubscription.for_list(list).excluding_ignored.distinct.pluck(:user_id)
    end

    # Public: Get subscriber IDs for a list using cursor-based pagination.
    #
    # list              - A list (e.g. Repository).
    # cursor            - Optional Integer cursor position (user ID).
    # cursor_direction  - Optional Symbol direction (:upwards or :downwards).
    # limit             - Optional Integer max number of results.
    # exclude_spammy_users - Optional Boolean to exclude spammy users.
    #
    # Returns Newsies::Responses::Array wrapping an array of Integer user IDs.
    sig do
      params(
        list: T.untyped,
        cursor: T.nilable(T.any(Integer, String)),
        cursor_direction: T.nilable(Symbol),
        limit: T.nilable(Integer),
        exclude_spammy_users: T.nilable(T::Boolean),
      ).returns(Newsies::Responses::Array)
    end
    def self.repository_subscriber_ids_by_cursor(list, cursor: nil, cursor_direction: nil, limit: nil, exclude_spammy_users: nil)
      GitHub.tracer.in_span("repository_subscriber_ids_by_cursor", kind: :internal) do
        GitHub.dogstats.distribution_time("notifications.subscriptions.repository_subscriber_ids_by_cursor") do
          options = {}
          options[:cursor] = cursor if cursor
          options[:cursor_direction] = cursor_direction if cursor_direction
          options[:limit] = limit if limit
          options[:exclude_spammy_users] = exclude_spammy_users unless exclude_spammy_users.nil?

          response = GitHub.newsies.subscriber_ids_by_cursor(list, options)
          tags = ["success:#{response.success?}", "type:#{list.class.name}"]
          GitHub.dogstats.increment("notifications.subscriptions.repository_subscriber_ids_by_cursor.count", tags:)
          response
        end
      end
    end

    # Return all user IDs muting a repository.
    sig { params(repository_id: Integer).returns(T::Array[Integer]) }
    def self.repository_muters(repository_id)
      list = Newsies::List.new("Repository", repository_id)
      Newsies::ListSubscription.for_list(list).only_ignored.distinct.pluck(:user_id)
    end

    # Get all subscribers to a thread, including those subscribed to the
    # thread in particular or to the list / thread type in general.
    #
    # This method should only be called as part of the Newsies notification
    # delivery pipeline.
    sig { params(list: Newsies::List, thread: Newsies::Thread).returns(T::Array[Newsies::Subscriber]) }
    def self.subscribers(list:, thread:)
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

    # Public: Delete thread subscriptions for provided user
    def self.delete_thread_subscriptions(user_id:, thread_subscription_ids:)
      GitHub.tracer.in_span("delete_thread_subscriptions", kind: :internal) do
        handle_errors(response_class: Newsies::Responses::Boolean, method: "delete_thread_subscriptions") do
          if FeatureFlag.vexi.enabled?(:notifyd_delete_thread_subscriptions, User.new(id: user_id), default: false)
            notifyd_schedule_delete_thread_subscriptions(user_id: user_id, thread_subscription_ids: thread_subscription_ids)
            GitHub.newsies.delete_thread_subscriptions(user_id: user_id, thread_subscription_ids: thread_subscription_ids)
          else
            GitHub.newsies.delete_thread_subscriptions(user_id: user_id, thread_subscription_ids: thread_subscription_ids)
          end
        end
      end
    end

    def self.unwatch_repositories(user, repositories)
      GitHub.tracer.in_span("unwatch_repositories", kind: :internal) do
        Newsies::ListSubscription.unsubscribe(user.id, repositories)
        GitHub.dogstats.count("newsies.unwatched_repositories.count", repositories.length)

        if FeatureFlag.vexi.enabled?(:notifyd_sync_respository_list, user, default: false)
          Notifyd::NewsiesService.new.unwatch(user: user, lists: repositories)
          GitHub.dogstats.count("notifyd.unwatched_repositories.count", repositories.length)
        end
      end
    end

    # Public: Asynchronously delete all the subscriptions and settings for a single list.
    #
    # list - A list Subject (e.g. Repository, Team)
    sig { params(list: Subject).void }
    def self.async_delete_list_subscriptions(list)
      # NOTE(abeaumont): Newsies deletes both subscriptions and web notifications,
      # as both actions are coupled in the same job, breaking separation of concerns.
      GitHub.newsies.async_delete_all_for_list(Newsies::List.new(list.type, list.id))
      GitHub.dogstats.increment("newsies.async_delete_list_subscriptions.count")
      if list.type == "Repository" && !GitHub.enterprise?
        Notifyd::MaintenanceService.new.delete_repository(list.id)
        GitHub.dogstats.increment("notifyd.async_delete_list_subscriptions.count")
      end
    end

    # Public: Asynchronously delete list subscriptions for a sequence of users.
    #
    # list - A list Subject (e.g. Repository, Team)
    # user_ids - An array of integer user IDs.
    # restorable_id - Optional restorable ID for persistence recovery
    sig { params(list: Subject, user_ids: T::Array[Integer], restorable_id: T.nilable(Integer)).void }
    def self.async_delete_list_subscriptions_for_users(list:, user_ids:, restorable_id: nil)
      # NOTE(abeaumont): Newsies deletes both subscriptions and web notifications,
      # as both actions are coupled in the same job, breaking separation of concerns.
      GitHub.newsies.async_delete_all_for_list_and_users(Newsies::List.new(list.type, list.id), user_ids, restorable_id: restorable_id)
      GitHub.dogstats.count("newsies.async_delete_list_subscriptions_for_users.count", user_ids.length)
      if list.type == "Repository" && !GitHub.enterprise?
        Notifyd::MaintenanceService.new.delete_repository_for_users(repo_id: list.id, user_ids: user_ids)
        GitHub.dogstats.count("notifyd.async_delete_list_subscriptions_for_users.count", user_ids.length)
      end
    end

    # Public: Delete all the subscriptions and settings for a user, asynchronously.
    sig { params(user_id: Integer).void }
    def self.async_delete_user_subscriptions(user_id)
      # NOTE(abeaumont): Newsies deletes both subscriptions and web notifications,
      # as both actions are coupled in the same job, breaking separation of concerns.
      GitHub.newsies.async_delete_all_for_user(user_id)
      GitHub.dogstats.increment("newsies.async_delete_user_subscriptions.count")
      if !GitHub.enterprise?
        Notifyd::MaintenanceService.new.delete_user(user_id)
        GitHub.dogstats.increment("notifyd.async_delete_user_subscriptions.count")
      end
    end

    # Public: Asynchronously delete all the subscriptions and settings for a user to a sequence of lists.
    #
    # user_id - A user identifier.
    # lists   - A sequence of Subjects of list type (e.g. Repository, Team)
    sig { params(user_id: Integer, lists: T::Array[Subject]).void }
    def self.async_delete_user_subscriptions_for_lists(user_id:, lists:)
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
    end

    # Public: Fetch list subscriptions for a user.
    #
    # Wraps Newsies::ListSubscription.subscriptions to encapsulate the Newsies
    # model access within the notifications package.
    #
    # user_id   - An Integer user id.
    # list_type - Optional String that matches the list_type.
    # set       - Optional Symbol (:subscribed, :ignored, :all).
    # page      - Optional Integer page number.
    # per_page  - Optional Integer items per page.
    # excluding - Optional Array of Newsies::List instances to exclude.
    # sort      - Optional String or Symbol sort direction.
    #
    # Returns an Array of Notification::Subscription.
    def self.list_subscriptions(user_id, list_type: nil, set: nil, page: nil, per_page: nil, excluding: nil, sort: nil)
      Newsies::ListSubscription.subscriptions(user_id, list_type: list_type, set: set, page: page, per_page: per_page, excluding: excluding, sort: sort)
    end

    # Public: Count a user's list subscriptions.
    #
    # Wraps Newsies::ListSubscription.count_subscriptions.
    #
    # user_id   - An Integer user id.
    # set       - Optional Symbol (:subscribed, :ignored, :all).
    # excluding - Optional Array of Newsies::List instances to exclude.
    # list_type - Optional String that matches the list_type.
    #
    # Returns an Integer count.
    def self.count_list_subscriptions(user_id, set: nil, excluding: nil, list_type: nil)
      Newsies::ListSubscription.count_subscriptions(user_id, set: set, excluding: excluding, list_type: list_type)
    end

    # Public: Fetch list IDs for a user's list subscriptions.
    #
    # Wraps Newsies::ListSubscription.subscriptions_list_ids.
    #
    # user_id   - An Integer user id.
    # list_type - Optional String that matches the list_type.
    # set       - Optional Symbol (:subscribed, :ignored, :all).
    # page      - Optional Integer page number.
    # per_page  - Optional Integer items per page.
    # excluding - Optional Array of Newsies::List instances to exclude.
    # sort      - Optional String or Symbol sort direction.
    #
    # Returns an Array of Integer list IDs.
    def self.list_subscriptions_list_ids(user_id, list_type: nil, set: nil, page: nil, per_page: nil, excluding: nil, sort: nil)
      Newsies::ListSubscription.subscriptions_list_ids(user_id, list_type: list_type, set: set, page: page, per_page: per_page, excluding: excluding, sort: sort)
    end

    # Public: Fetch list subscriptions for a user using cursor-based pagination.
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
    # Returns a Newsies::Responses::Array of Newsies::ListSubscription::Subscription objects.
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
        tags = ["success:#{response.success?}"]
        GitHub.dogstats.increment("notifications.subscriptions.repository_subscriptions_by_cursor.count", tags:)
        response
      end
    end

    # Public: Get the list subscriptions for the given user and lists.
    #
    # Wraps GitHub.newsies.user_list_subscriptions to encapsulate the Newsies
    # service access within the notifications package.
    #
    # user_id - An Integer user id.
    # lists   - An Array of Newsies::List instances to scope to.
    #
    # Returns Newsies::Responses::Array instance.
    def self.user_list_subscriptions(user_id, lists)
      GitHub.tracer.in_span("user_list_subscriptions", kind: :internal) do
        response = GitHub.dogstats.distribution_time("notifications.subscriptions.user_list_subscriptions") do
          GitHub.newsies.user_list_subscriptions(user_id, lists)
        end
        types = lists.map(&:type).uniq
        list_type = if types.empty?
          "unknown"
        elsif types.length > 1
          "mixed"
        else
          types.first
        end
        tags = ["type:#{list_type}", "success:#{response.success?}"]
        GitHub.dogstats.increment("notifications.subscriptions.user_list_subscriptions.count", tags:)
        response
      end
    end

    # Public: Fetch thread type subscriptions for a user.
    #
    # Wraps Newsies::ThreadTypeSubscription.subscriptions to encapsulate the
    # Newsies model access within the notifications package.
    #
    # user_id     - An Integer user id.
    # page        - Optional Integer page number.
    # per_page    - Optional Integer items per page.
    # excluding   - Optional Array of Newsies::List instances to exclude.
    # sort        - Optional Symbol sort direction (:asc, :desc).
    # list_type   - Optional String list type (default: "Repository").
    # thread_type - Optional String thread type filter.
    #
    # Returns an Array of Notification::Subscription.
    def self.thread_type_subscriptions(user_id, page: nil, per_page: nil, excluding: nil, sort: :desc, list_type: "Repository", thread_type: nil)
      Newsies::ThreadTypeSubscription.subscriptions(user_id, page: page, per_page: per_page, excluding: excluding, sort: sort, list_type: list_type, thread_type: thread_type)
    end

    # Public: Count a user's thread type subscriptions.
    #
    # Wraps Newsies::ThreadTypeSubscription.count_subscriptions.
    #
    # user_id     - An Integer user id.
    # list_type   - Optional String list type (default: "Repository").
    # thread_type - Optional String thread type filter.
    #
    # Returns an Integer count.
    def self.count_thread_type_subscriptions(user_id, list_type: "Repository", thread_type: nil)
      Newsies::ThreadTypeSubscription.count_subscriptions(user_id, list_type: list_type, thread_type: thread_type)
    end

    # Public: Fetch list IDs for a user's thread type subscriptions.
    #
    # Wraps Newsies::ThreadTypeSubscription.subscriptions_list_ids.
    #
    # user_id     - An Integer user id.
    # page        - Optional Integer page number.
    # per_page    - Optional Integer items per page.
    # excluding   - Optional Array of Newsies::List instances to exclude.
    # sort        - Optional Symbol sort direction (:asc, :desc).
    # list_type   - Optional String list type (default: "Repository").
    # thread_type - Optional String thread type filter.
    #
    # Returns an Array of Integer list IDs.
    def self.thread_type_subscriptions_list_ids(user_id, page: nil, per_page: nil, excluding: nil, sort: :desc, list_type: "Repository", thread_type: nil)
      Newsies::ThreadTypeSubscription.subscriptions_list_ids(user_id, page: page, per_page: per_page, excluding: excluding, sort: sort, list_type: list_type, thread_type: thread_type)
    end

    # Public: Get the thread type subscriptions for the given user and threads.
    #
    # Wraps GitHub.newsies.user_thread_type_subscriptions to encapsulate the
    # Newsies service access within the notifications package.
    #
    # user_id - An Integer user id.
    # threads - An Array of Newsies::Thread instances to scope to.
    #
    # Returns Newsies::Responses::Array instance.
    def self.user_thread_type_subscriptions(user_id, threads)
      GitHub.tracer.in_span("user_thread_type_subscriptions", kind: :internal) do
        response = GitHub.dogstats.distribution_time("notifications.subscriptions.user_thread_type_subscriptions") do
          GitHub.newsies.user_thread_type_subscriptions(user_id, threads)
        end
        tags = ["success:#{response.success?}"]
        GitHub.dogstats.increment("notifications.subscriptions.user_thread_type_subscriptions.count", tags:)
        response
      end
    end

    # Public: Get a reason string from any valid reason type
    #
    # reason  - Optional String, Symbol or Hash reason
    #           (ie: "mention", :mention, {:reason => :mention, :force => true}).
    def self.valid_reason_from(reason)
      options = Newsies::ThreadSubscribeOptions.from(reason)
      Newsies::Reasons.valid_reason_from(options.reason).to_s
    end

    # Public: Fetch list-level subscriber user IDs for a repository using cursor-based pagination.
    #
    # repository_id - Integer repository ID.
    # after         - Integer cursor (user_id). Returns users with user_id > after. Use 0 for the first batch.
    # limit         - Integer max number of user IDs to return per batch.
    #
    # Returns Array<Integer> of user IDs, sorted ascending.
    sig { params(repository_id: Integer, after: Integer, limit: Integer).returns(T::Array[Integer]) }
    def self.repository_subscriber_ids(repository_id, after: 0, limit: 1000)
      list = Newsies::List.new("Repository", repository_id)
      Newsies::ListSubscription.for_list(list)
        .where("user_id > ?", after).order(user_id: :asc)
        .limit(limit).distinct.pluck(:user_id)
    end

    # Public: Fetch thread-type subscriber user IDs for a repository using cursor-based pagination.
    #
    # repository_id - Integer repository ID.
    # after         - Integer cursor (user_id). Returns users with user_id > after.
    # limit         - Integer max number of user IDs to return per batch.
    #
    # Returns Array<Integer> of user IDs, sorted ascending.
    sig { params(repository_id: Integer, after: Integer, limit: Integer).returns(T::Array[Integer]) }
    def self.repository_thread_type_subscriber_ids(repository_id, after: 0, limit: 1000)
      list = Newsies::List.new("Repository", repository_id)
      Newsies::ThreadTypeSubscription.for_list(list)
        .where("user_id > ?", after).order(user_id: :asc)
        .limit(limit).distinct.pluck(:user_id)
    end

    # Public: Fetch thread-level subscriber user IDs for a repository using cursor-based pagination.
    #
    # repository_id - Integer repository ID.
    # after         - Integer cursor (user_id). Returns users with user_id > after.
    # limit         - Integer max number of user IDs to return per batch.
    #
    # Returns Array<Integer> of user IDs, sorted ascending.
    sig { params(repository_id: Integer, after: Integer, limit: Integer).returns(T::Array[Integer]) }
    def self.repository_thread_subscriber_ids(repository_id, after: 0, limit: 1000)
      list = Newsies::List.new("Repository", repository_id)
      Newsies::ThreadSubscription.for_list(list)
        .where("user_id > ?", after).order(user_id: :asc)
        .limit(limit).distinct.pluck(:user_id)
    end

    # Public: Fetch unique subscriber user IDs for a repository across all subscription types.
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
      ids = repository_subscriber_ids(repository_id, after:, limit:) +
            repository_thread_type_subscriber_ids(repository_id, after:, limit:) +
            repository_thread_subscriber_ids(repository_id, after:, limit:)
      ids.uniq.sort.first(limit)
    end

    # Public: Count subscriber user IDs for a repository across all subscription types.
    #
    # Returns the sum of per-type unique subscriber counts. This is an upper
    # bound — users subscribed via multiple types are counted multiple times.
    sig { params(repository_id: Integer).returns(Integer) }
    def self.count_all_repository_subscribers(repository_id)
      list = Newsies::List.new("Repository", repository_id)

      Newsies::ListSubscription.for_list(list).distinct.count(:user_id) +
        Newsies::ThreadTypeSubscription.for_list(list).distinct.count(:user_id) +
        Newsies::ThreadSubscription.for_list(list).distinct.count(:user_id)
    end

    # Public: Returns subscribed repositories for a user, filtering out
    # inaccessible, deleted, or invisible repositories. Enqueues cleanup
    # jobs for any bad subscriptions found.
    #
    # user             - A User.
    # page             - An optional Integer for which page to return.
    # per_page         - An optional Integer for how many results to return per page.
    # excluding        - An optional Array of list_ids to be excluded on the MySQL side.
    # sort             - An optional String or Symbol direction to sort (:asc, "asc", :desc, "desc").
    #
    # Returns Newsies::Responses::Array of Repository instances.
    def self.subscribed_repositories(user, page: nil, per_page: nil, excluding: nil, sort: nil)
      GitHub.tracer.in_span("subscribed_repositories", kind: :internal) do
        GitHub.dogstats.distribution_time("notifications.subscriptions.subscribed_repositories") do
          response = GitHub.newsies.subscribed_repositories(user, set: :subscribed, page: page, per_page: per_page, excluding: excluding, sort: sort)
          tags = ["success:#{response.success?}"]
          GitHub.dogstats.increment("notifications.subscriptions.subscribed_repositories.count", tags:)
          response
        end
      end
    end

    # Public: Count a user's subscribed repositories.
    #
    # user      - A User.
    # excluding - An optional Array of repository ids to exclude.
    #
    # Returns a Newsies::Responses::Count instance.
    def self.count_subscriptions(user, excluding: nil)
      GitHub.tracer.in_span("count_subscriptions", kind: :internal) do
        GitHub.dogstats.distribution_time("notifications.subscriptions.count_subscriptions") do
          response = GitHub.newsies.count_subscriptions(user, set: :subscribed, excluding: excluding)
          tags = ["success:#{response.success?}"]
          GitHub.dogstats.increment("notifications.subscriptions.count_subscriptions.count", tags:)
          response
        end
      end
    end

    # Public: Checks if a user has exceeded the maximum number of repository
    # subscriptions.
    #
    # user         - A User.
    # subscribable - A subscribable object (e.g. Repository).
    #
    # Returns a Newsies::Responses::Boolean instance.
    def self.subscription_limit_exceeded?(user, subscribable)
      Newsies::Responses::Boolean.new do
        next false if GitHub.enterprise?
        next false unless FeatureFlag.vexi.enabled?(:enable_notifications_repository_subscription_limits, user, default: false)
        next false if FeatureFlag.vexi.enabled?(:enable_notifications_repository_subscription_limits_override, user, default: false)

        if subscribable.is_a?(::Repository) && count_subscriptions(user) >= Newsies::Service::MAX_REPOSITORY_SUBSCRIPTIONS_PER_USER
          GitHub.dogstats.count("api.notifications.subscription_limit_exceeded", 1)
          next true
        end
        next false
      end
    end

    private

    private_class_method def self.notifyd_sync_repository_list?(user, list)
      list.is_a?(Repository) && FeatureFlag.vexi.enabled?(:notifyd_sync_respository_list, user, default: false)
    end

    private_class_method def self.handle_errors(raise_errors: false, response_class: nil, method:, &block)
      notify_system = response_class == Notifyd::Responses::Boolean ? "notifyd" : "newsies"
      begin
        yield
      rescue => e
        GitHub.dogstats.increment(EXCEPTIONS_STAT, tags: ["system:#{notify_system}"])
        NotificationsFailbot.report(e, "service.name": notify_system, "code.function": method)
        raise e if raise_errors

        response = response_class.new
        if response.respond_to?(:success)
          response.success = false
        end

        response
      end
    end
  end
end
