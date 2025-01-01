# typed: true
# frozen_string_literal: true

require "newsies/subscriber_set"

require "newsies/objects/list"
require "newsies/objects/thread"
require "newsies/objects/comment"
require "newsies/managers/web"
require "newsies/handlers/email_handler"
require "newsies/handlers/web_handler"
require "newsies/locator"

module Newsies

  # The external Newsies object.  This wires subscription backends,
  # and also manages the backend for Settings.
  # This is the interface accessed by all outside code.
  class Service
    include Reasons

    include GitHub::Tracing
    trace_method :trigger
    trace_method :get_and_update_settings
    trace_method :update_settings
    trace_method :auto_subscribe
    trace_method :notify_auto_subscribed
    trace_method :mark_lists_as_notified
    trace_method :subscribe_to_thread
    trace_method :subscribe_all_to_thread
    trace_method :subscribe_to_list
    trace_method :subscribe_to_thread_types
    trace_method :unsubscribe
    trace_method :unsubscribe_from_thread
    trace_method :process_subscription_update
    trace_method :delete_thread_subscriptions
    trace_method :ignore_list
    trace_method :ignore_thread
    trace_method :ignored

    attr_reader :handlers, :web

    if Rails.env.test?
      # Needed temporarily for low level unit tests
      attr_reader :list_subs, :thread_subs
    end

    DEFAULT_EMAIL_ONLY_NOTIFICATIONS_CUTOFF_DATE = Time.utc(2016, 01, 07).freeze
    DEFAULT_AUTO_SUBSCRIBE_CUTOFF_DATE = Time.utc(2016, 07, 27).freeze
    DEFAULT_EMAIL_WEB_NOTIFICATIONS_CUTOFF_DATE = Time.utc(2022, 06, 10).freeze

    def initialize
      @settings_store = SettingsStore.new
      @web = Web.new
      @handlers = [WebHandler.new, EmailHandler.new]
    end

    # This is the external endpoint for triggering notification delivery.
    #
    # object                  - The object that is generating the notification.
    # event_time              - (Required) Time that the notification generating object was created/update
    #                           This should be the time that _this_ notification is relevant for.
    # recipient_ids           - (Optional) Array<Integer> of user IDs for those who should receive the
    #                           notification. deliver the notifications to. Default of `nil` causes us to
    #                           deliver notifications to all computed subscribers of the given object.
    # reason                  - (Optional) String or Symbol defining the reason for which the notification is
    #                           being sent. Default of `nil` causes the reason to be derived from the
    #                           subscription record(s) for the notification recipient.
    # priority                - Priority of this notification, :low or :high, defaults :high
    # is_update               - Boolean indicating whether this notification is due to an update event.
    # spam_check_delay_served - Boolean indicating whether the spam check delay has already been served.
    #
    # Returns nothing.
    def trigger(object, event_time:, recipient_ids: nil, reason: nil, priority: nil, is_update: false, spam_check_delay_served: false)
      return unless ::GitHub.send_notifications?

      author = object.try(:notifications_author)
      job_class = DeliverNotificationsJob
      args = [
        object.class.name,
        object.id,
        recipient_ids,
        reason
      ]
      kwargs = {
        enqueued_at: Time.now.to_f,
        event_time: event_time,
        priority: priority,
        is_update: is_update
      }.compact

      # Wait for a short period to give async spam checks time to finish https://github.com/github/notifications/issues/296
      if GitHub::SpamChecker.external_spamminess_check_enabled?
        job_class = job_class.set(wait: GitHub::SpamChecker::DELAY_FOR_EXTERNAL_CHECKS)
      end

      job_class.perform_later(*args, **kwargs)

      nil
    end

    # Public: Get and update the settings for a user.
    #
    # user - The User whose settings we are going to get and update.
    #
    # Yields Newsies::Settings instance for modification prior to update.
    #
    # Returns Newsies::Responses::Boolean instance with value of true if found
    # and updated or false if not found or found but not updated.
    def get_and_update_settings(user, &block)
      Responses::Boolean.new do
        settings = settings(user).value!
        yield settings
        update_settings(user, settings).value!
      end
    end

    # Public: Get the settings or default settings for a user.
    #
    # user - The User whose settings we are going to get.
    #
    # Returns Newsies::Responses::Settings instance.
    sig { params(user: T.any(User, Integer)).returns(Responses::Settings) }
    def settings(user)
      Responses::Settings.new do
        settings = @settings_store.get(user)
        if settings.new?
          default_user_settings(user)
        else
          settings.user = user
          settings
        end
      end
    end

    # Public: Update a users settings to the settings provided.
    #
    # user - The User whose settings we are going to update.
    #
    # Returns Newsies::Responses::Boolean instance.
    def update_settings(user, settings)
      Responses::Boolean.new { @settings_store.set(user, settings) }
    end

    def async_subscribe_users_to_repository(repo_id, user_ids, repository_creator_id = nil)
      AutoSubscribeUsersToRepositoryJob.perform_later(repo_id, user_ids, repository_creator_id)
    end

    # Public: Enqueues an instance of Newsies::AutoSubscribeUserToRepositoriesJob to auto subscribe
    # a given user to the list of repositories.
    #
    # The job belongs to the notifications queue, which can be paused in case of the notifications DB cluster
    # being down. Ideally this would happen automatically in case of a failure.
    #
    # user   - A User or a Newsies::Settings object.  If a User is
    #          given, fetch the Newsies::Settings with #settings.
    # repository_ids - An Array of repository_ids
    # notify - Boolean that determines if the user is notified.
    #
    # Returns nothing
    def async_auto_subscribe(user, repository_ids, notify = true)
      Newsies::AutoSubscribeUserToRepositoriesJob.perform_later(user.id, repository_ids, notify)
    end

    # Public: Subscribes a User to a Repository, unless they are ignoring it.
    #
    #     kyle = User.find_by_login("kneath")
    #     github = Repository.nwo 'github/github'
    #     GitHub.newsies.auto_subscribe kyle, github
    #
    # user   - A User or a Newsies::Settings object.  If a User is
    #          given, fetch the Newsies::Settings with #settings.
    # repo   - A Repository.
    # notify - Boolean that determines if the user is notified.
    #
    # Returns true if the user was auto subscribed, or false.
    def auto_subscribe(user, repo, notify = true, auto_subscribe_to_own_repos = false)
      Responses::Boolean.new do
        GitHub.dogstats.time("newsies.auto_subscribe") do
          result = T.let(false, T::Boolean)

          user_object = user.is_a?(User) ? user : User.find(user.id)
          # Auto-subscribing to forks is an abuse vector
          next false if repo.fork? && !GitHub.enterprise?

          # Don't subscribe users if ignoring
          all_lists = [repo, repo.parent, repo.root]
          all_lists.compact!
          all_lists.uniq!
          ignored = ListSubscription.ignored(user.id, Newsies::List.to_objects(all_lists))
          next false if ignored.any?

          newsies_list = Newsies::List.to_object(repo)

          # Don't subscribe users if they are already subscribed to a subset of thread types
          next false if ThreadTypeSubscription.for_user(user.id).for_list(newsies_list).any?

          settings = user.respond_to?(:auto_subscribe?) ? user : settings(user).value!

          if auto_subscribe_to_own_repos || settings.try(:auto_subscribe?)
            notify = false if user.id == repo.owner_id

            ApplicationRecord::Domain::Notifications.transaction do
              ListSubscription.auto_subscribe(user.id, newsies_list, notify)
              ThreadTypeSubscription.unsubscribe_from_all_thread_types_for_list(user.id, newsies_list)
              async_notify_list_subscription_state_change(user.id, newsies_list)
              result = true
            end

            if notifyd_sync_repository_list?(user, repo)
              Notifyd::NewsiesService.new.watch(user: user, list: repo, is_auto_susbcription: true)
            end
          end

          result
        end
      end
    end

    # Public: Yields a user setting and Array of repositories that the user has
    # not been notified of and marks them as notified.
    #
    # block - A block taking a Newsies::Settings object and Array of
    #         Repository instances.
    #
    # Returns Newsies::Response.
    def notify_auto_subscribed(&block)
      Response.new do
        ListSubscription.subscriptions_to_notify(list_type: "Repository") do |user_id, lists|
          list_ids = lists.map(&:id)
          if user = User.find_by(id: user_id)
            begin
              repositories = Repository.includes(:owner).where(id: list_ids)
              block.call(settings(user).value!, repositories)
            ensure
              missing_list_ids = list_ids - repositories&.map(&:id)
              missing_lists = missing_list_ids.map { |id| Newsies::List.new("Repository", id) }
              Notifications::Subscriptions.cleanup_list_subscriptions(user, missing_lists, ["reason:no-list", "workflow:notify_auto_subscribed"])
            end
          else
            lists = list_ids.map { |id| Newsies::List.new("Repository", id) }
            Notifications::Subscriptions.cleanup_all_list_subscriptions(user_id, lists, ["reason:no-user", "workflow:notify_auto_subscribed"])
          end
        end
      end
    end

    # Public: Marks the user as having been notified about the given lists.
    #
    # user - A User.
    # list - An Array of list objects.
    #
    # Returns Newsies::Response with nil value.
    def mark_lists_as_notified(user, lists)
      Response.new { ListSubscription.notified(user.id, Newsies::List.to_objects(lists)) }
    end

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
    def subscribe_to_thread(user, list, thread, reason = nil, events = [])
      Responses::Boolean.new do
        GitHub.dogstats.time("newsies.thread_subscribe") do
          next false unless user&.newsies_enabled?

          newsies_list = Newsies::List.to_object(list)
          list_subscription_status = ListSubscription.status(user.id, newsies_list)

          next false if list_subscription_status.ignored?

          unless list.try(:readable_by?, user)
            GitHub.dogstats.increment(
              "newsies.delivery.user_not_subscribable",
              tags: ["class:#{Newsies::Thread.to_type(thread).underscore}"])
          end

          options = ThreadSubscribeOptions.from(reason)
          options.reason = reason_sym = valid_reason_from(options.reason)
          options.force = forced_reason?(reason_sym) unless reason.is_a?(Hash)
          newsies_thread = Newsies::Thread.to_object(thread, list: newsies_list)
          ThreadSubscription.subscribe(user.id, newsies_thread, options, events)

          true
        end
      end
    end

    # Public: Subscribe an array of users to a thread.
    #
    # user - An array of Users.
    # list - A list (ie: Repository).
    # thread - A thread (ie: Issue, Commit, etc.).
    # reason - Optional String, Symbol or Hash reason
    #          (ie: "mention", :mention, {:reason => :mention, :force => true}).
    #
    # Returns Newsies::Responses::Boolean if the operation succeeds even if any user in the list can't be subscribed
    def subscribe_all_to_thread(users, list, thread, reason = nil)
      Responses::Boolean.new do
        GitHub.dogstats.time("newsies.thread_subscribe_all") do
          responses = subscription_status_all(users, list).value!
          subscribable_users = users.select.with_index do |user, index|
            next false unless user && user.newsies_enabled?
            response = responses[index]
            next false if response.ignored?
            true
          end

          options = ThreadSubscribeOptions.from(reason)
          options.reason = reason_sym = valid_reason_from(options.reason)
          options.force = forced_reason?(reason_sym) unless reason.is_a?(Hash)
          newsies_list = Newsies::List.to_object(list)
          newsies_thread = Newsies::Thread.to_object(thread, list: newsies_list)
          subscribable_users.each_slice(GitHub.subscribed_users_batch_size).each do |users|
            ThreadSubscription.subscribe_all(users.map(&:id), newsies_thread, options)
          end
          true
        end
      end
    end

    # Currently this is only used by commit comments to asyncronously subscribe
    # for the :author, or :comment reasons, no team is needed
    def async_subscribe_to_thread(user_id, repository_id, commit_oid, reason = nil)
      SubscribeUserToThreadJob.perform_later(user_id, repository_id, commit_oid, reason)
    end

    # Public: Subscribe a user to a list. See the background job
    # SubscribeToListNotificationsJob to call this asynchronously.
    #
    # user - A User.
    # list - A list (ie: Repository, Team).
    #
    # Returns Newsies::Responses::Boolean.
    def subscribe_to_list(user, list)
      Responses::Boolean.new do
        GitHub.dogstats.time("newsies.list_subscribe") do
          next false unless user && user.newsies_enabled?

          newsies_list = Newsies::List.to_object(list)
          ListSubscription.subscribe(user.id, newsies_list)
          ThreadTypeSubscription.unsubscribe_from_all_thread_types_for_list(user.id, newsies_list)
          async_notify_list_subscription_state_change(user.id, newsies_list)
          if notifyd_sync_repository_list?(user, list)
            Notifyd::NewsiesService.new.watch(user: user, list: list)
          end
          true
        end
      end
    end

    # Public: Subscribe a user to a thread type, will remove any existing
    #         watching/ignored entry for the list
    #
    # user                - A User.
    # list                - A list (i.e. Repository, Team)
    # thread_type_classes - Array<A class of the thread type, i.e. Release>
    #
    # Return Newsies::Responses::Boolean
    def subscribe_to_thread_types(user, list, thread_type_classes)
      thread_types = thread_type_classes.map { |thread_type_class| Newsies::Object.type_from_class(thread_type_class) }

      Responses::Boolean.new do
        GitHub.dogstats.time("newsies.thread_type_subscribe") do
          next false unless user&.newsies_enabled?
          newsies_list = Newsies::List.to_object(list)

          ListSubscription.unsubscribe(user.id, [newsies_list])
          ThreadTypeSubscription.subscribe_to_thread_types(user.id, newsies_list, thread_types)
          async_notify_list_subscription_state_change(user.id, newsies_list)
          if notifyd_sync_repository_list?(user, list)
            if thread_type_classes.nil? || thread_type_classes.empty?
              Notifyd::NewsiesService.new.unwatch(user: user, lists: [list])
            else
              Notifyd::NewsiesService.new.watch(user: user, list: list, thread_types: thread_type_classes.map(&:name))
            end
          end
          true
        end
      end
    end

    # Public: Checks the subscription status for the user and the list or
    # thread object.
    #
    # user    - A User.
    # list    - A list (Repository or Team).
    # thread  - A thread (Issue, Discussion, or Commit).
    #
    # Returns Newsies::Responses::Subscription instance.
    def subscription_status(user, list, thread = nil)
      tags = ["list:#{Newsies::List.to_type(list).underscore}"]
      tags << "thread:#{Newsies::Thread.to_type(thread).underscore}" if thread

      Responses::Subscription.new do
        GitHub.dogstats.time("newsies.subscription_status", tags: tags) do
          newsies_list = Newsies::List.to_object(list)

          if thread
            newsies_thread = Newsies::Thread.to_object(thread, list: newsies_list)
            ThreadSubscription.status(user.id, newsies_thread)
          else
            list_subscription = ListSubscription.status(user.id, newsies_list)
            list_subscription.thread_types = ThreadTypeSubscription.subscribed_thread_types(user.id, newsies_list)
            list_subscription
          end
        end
      end
    end

    # Public: Checks the subscription status for an array of users and the list or
    # thread object.
    #
    # user    - An array of Users.
    # list    - A list (Repository or Team).
    # thread  - A thread (Issue, Discussion, or Commit).
    #
    # Returns Newsies::Responses::Subscription instance wrapping an array of Subscription
    def subscription_status_all(users, list, thread = nil)
      Responses::Array.new do
        statuses = []
        if thread
          users.each_slice(GitHub.subscribed_users_batch_size).each do |batched_users|
            newsies_list = Newsies::List.to_object(list)
            newsies_thread = Newsies::Thread.to_object(thread, list: newsies_list)
            T.unsafe(statuses).push(*ThreadSubscription.status_all(batched_users.map(&:id), newsies_thread))
          end
        else
          users.each_slice(GitHub.subscribed_users_batch_size).each do |batched_users|
            newsies_list = Newsies::List.to_object(list)
            user_ids = batched_users.map(&:id)
            list_subscriptions = ListSubscription.status_all(user_ids, newsies_list)

            thread_types_by_user_id = ThreadTypeSubscription.
              for_list(newsies_list).
              for_users(user_ids).
              pluck(:user_id, :thread_type).
              group_by(&:first).
              transform_values { |value| value.flat_map(&:second) }

            list_subscriptions.each_with_index do |list_subscription, index|
              list_subscription.thread_types = thread_types_by_user_id.fetch(user_ids[index], [])
            end

            statuses.push(*list_subscriptions)
          end
        end
        statuses
      end
    end

    # Public: retrieves the subscription status for a user and some list ids.
    #
    # user     - A User.
    # list_ids - the Entity ids to check
    #
    # Returns Newsies::Responses::Array instance.
    def list_subscriptions(user, list_ids)
      Responses::Array.new do
        lists = list_ids.compact.uniq.map do |id|
          Newsies::List.new("Repository", id)
        end
        ListSubscription.subscriptions_find_many(user.id, lists)
      end
    end

    # Public: Get the subscriptions for the given user and lists.
    #
    # user_id - A User id.
    # list - the lists to scope to.
    #
    # Returns Newsies::Responses::Array instance.
    def user_list_subscriptions(user_id, lists)
      Responses::Array.new do
        GitHub.dogstats.time("newsies.user_list_subscriptions") do
          Newsies::ListSubscription.for_user(user_id).for_lists(lists)
        end
      end
    end

    # Public: Get the subscriptions for the given user and threads.
    #
    # user_id - A User id.
    # threads - the threads to scope to.
    #
    # Returns Newsies::Responses::Array instance.
    def user_thread_subscriptions(user_id, threads)
      Responses::Array.new do
        GitHub.dogstats.time("newsies.user_thread_subscriptions") do
          Newsies::ThreadSubscription.for_user(user_id).for_threads(threads)
        end
      end
    end

    # Public: Get the subscribed repo ids for the given user, repository ids and thread type.
    #
    # user_id        - Integer user id
    # repository_ids - Array of Integers of repository ids
    # thread_type    - String thread type.
    #
    # Returns Array[Integer].
    def subscribed_repository_ids(user_id, repository_ids, thread_type)
      subscribed_repository_ids = T.let([], T::Array[Integer])
      repository_ids = repository_ids.to_set

      # find all repos the user is subscribed for all events
      repository_ids.each_slice(1000).each do |batched_repositories|
        newsies_lists = batched_repositories.map { |repository_id| Newsies::List.new("Repository", repository_id) }
        list_subscriptions = ListSubscription.for_user(user_id).for_lists(newsies_lists).excluding_ignored

        list_subscriptions.each do |list_subscription|
          subscribed_repository_ids.push(list_subscription.list_id)
        end
      end

      repository_ids.delete(subscribed_repository_ids)

      # find repos the user is subscribed to for the given thread type
      repository_ids.each_slice(1000).each do |batched_repositories|
        newsies_lists = batched_repositories.map { |repository_id| Newsies::List.new("Repository", repository_id) }
        thread_types_by_user_id = ThreadTypeSubscription.
          for_user(user_id).
          for_lists(newsies_lists).
          for_thread_type(thread_type)

        thread_types_by_user_id.each do |subscription|
          subscribed_repository_ids.push(subscription.list_id)
        end
      end

      subscribed_repository_ids
    end

    # Public: Get the subscriptions for the given user and types for the
    # given threads.
    #
    # user_id - A User id.
    # threads - the threads to scope the returned types to.
    #
    # Returns Newsies::Responses::Array instance.
    def user_thread_type_subscriptions(user_id, threads)
      Responses::Array.new do
        GitHub.dogstats.time("newsies.user_thread_type_subscriptions") do
          Newsies::ThreadTypeSubscription.for_user(user_id).for_threads(threads)
        end
      end
    end

    # Public: Unsubscribes a User from a List or Thread.
    #
    # NOTE: calling this method with a thread is deprecated, prefer `unsubscribe_from_thread`
    #
    # user - A User.
    # list - An List or Array of List objects of a single type (if no thread is given).
    #
    # Returns Newsies::Response instance.
    def unsubscribe(user, list)
      Response.new do
        GitHub.dogstats.time("newsies.list_unsubscribe") do
          lists = Newsies::List.to_objects(Array(list))
          ListSubscription.unsubscribe(user.id, lists)
          ThreadTypeSubscription
            .unsubscribe_from_all_thread_types_for_multiple_lists(user.id, lists)
          lists.each do |newsies_list|
            async_notify_list_subscription_state_change(user.id, newsies_list)
          end
          if notifyd_sync_repository_list?(user, list)
            Notifyd::NewsiesService.new.unwatch(user: user, lists: [list])
          end
        end
      end
    end

    # Public: Ensures that the user will not receive notifications from the thread
    #         until they are subscribed again.
    #
    # thread - A thread object (e.g. Issue / PullRequest / DiscussionPost)
    #
    # This method should be preferred over `unsubscribe(user, list, thread)`, or `ignore_thread`
    # as it will check the user's current list/thread-type subscriptions to ensure we do the
    # correct thing with the thread subscription (delete it or set it to ignored) to ensure
    # the user is no longer notified.
    def unsubscribe_from_thread(user, thread)
      Response.new do
        ThreadSubscriptionManager.unsubscribe_from_thread(user, thread.notifications_list, thread.notifications_thread)
      end
    end


    # Public: Processes various subscription update actions
    #
    # subscribable - A thread object (e.g. Issue / PullRequest / DiscussionPost)
    # state - the desired end state for the subscription
    # user - the user who is performing the action
    # types - optional. thread types to subscribe to

    def process_subscription_update(subscribable:, state:, user:, types: [], events: [])
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
          user.watch_repo(subscribable)
        when "ignored"
          user.ignore_repo(subscribable)
        when "releases_only"
          user.subscribe_to_thread_types(subscribable, [Release])
        end
      when ::Team
        case state
        when "unsubscribed"
          unsubscribe(user, subscribable)
        when "subscribed"
          subscribe_to_list(user, subscribable)
        when "ignored"
          ignore_list(user, subscribable)
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
          subscribable.unsubscribe(user)
        when "subscribed"
          subscribable.subscribe(user, :manual)
        when "custom"
          subscribable.subscribe(user, :manual, events)
        end
      when ::DiscussionPost
        case state
        when "unsubscribed", "ignored"
          unsubscribe_from_thread(user, subscribable)
        when "subscribed"
          subscribable.subscribe(user, :manual)
        end
      end
    end

    # Public: Delete specific thread subscriptions for a given user id.
    #
    # user_id                 - A User id.
    # thread_subscription_ids - An array of thread subscription ids.
    #
    # Returns Newsies::Response instance.
    def delete_thread_subscriptions(user_id:, thread_subscription_ids:)
      Response.new do
        GitHub.dogstats.time("newsies.delete_thread_subscriptions") do
          batches = ThreadSubscription
                      .for_user(user_id)
                      .where(id: thread_subscription_ids)
                      .in_batches(of: ThreadSubscription::DELETE_BATCH_SIZE)
          T.must(batches).each(&:destroy_all)
        end

        nil
      end
    end

    # Public: Copy the thread subscribers from old_thread to new_thread
    #
    # This ensures that users who were receiving notifications for the old thread continue
    # to receive notifications for the new thread.
    #
    # Notes:
    #   - this method should be called before old_thread is destroyed, but as soon as this method returns
    #     it is safe to delete old_thread
    #   - users who don't have access to the new thread will be copied temporarily, but
    #     these subscriptions will be "useless" as the users will not be able to receive the notifications.
    #     They will eventually be deleted.
    #   - any user only receiving notifications on the old thread because they are subscribed to the list
    #     will not be copied
    #
    # old_thread - thread to copy subscribers from, e.g. Issue
    # new_threae - thread to copy subscribers to, e.g. Issue
    def async_copy_thread_subscribers(old_thread, new_thread)
      CopyThreadSubscribersJob.copy_thread_subscribers(old_thread, new_thread)
    end

    # Public: Enqueues a job to delete all data in newsies for a given user and multiple lists.
    #
    # user_id - Integer user id to cleanup
    # lists   - An array of Newsies::List objects
    sig { params(user_id: Integer, lists: T::Array[List]).void }
    def async_delete_all_for_user_and_lists(user_id:, lists:)
      lists.each_slice(Newsies::MaintenanceBaseJob::MAX_LIST_SIZE) do |batched_lists|
        list_hashes = batched_lists.map do |list|
          { type: List.to_type(list), id: List.to_id(list) }
        end
        DeleteAllForUserAndListsJob.perform_later(user_id, list_hashes)
      end
    end

    def async_delete_all_for_user_and_repository_owner(user_id, owner_id, subscription_type)
      DeleteAllForUserAndRepositoryOwnerJob.perform_later(user_id, owner_id, subscription_type)
    end

    def async_delete_for_user_and_all_repositories(user_id, list_type, subscription_type)
      DeleteForUserAndAllRepositoriesJob.perform_later(user_id, list_type, subscription_type)
    end

    # Public: Enqueues a job to delete all data in newsies for a given user
    sig { params(user_id: Integer).void }
    def async_delete_all_for_user(user_id)
      DeleteAllForUserJob.perform_later(user_id)
    end

    # Public: Enqueues a job to delete all data in newsies
    #         for a given list and multiple users
    #
    # list     - A newsies list to clean up for
    # user_ids - An array of user_ids
    sig { params(list: List, user_ids: T::Array[Integer]).void }
    def async_delete_all_for_list_and_users(list, user_ids)
      user_ids.each_slice(Newsies::MaintenanceBaseJob::MAX_LIST_SIZE) do |batched_user_ids|
        DeleteAllForListAndUsersJob.perform_later(list.type, list.id, batched_user_ids)
      end
    end

    # Public: Enqueues a job to delete all data in newsies for a given list
    #
    # list     - A Newsies list.
    sig { params(newsies_list: List).void }
    def async_delete_all_for_list(newsies_list)
      DeleteAllForListJob.perform_later(newsies_list.type, newsies_list.id)
    end

    # Public: Enqueues a job to delete all data in newsies for a given thread
    #
    # list     - A list (e.g. Repository or Team) to clean up for
    # thread   - A thread (e.g. Issue or DiscussionPost) to clean up for
    #   ensure_thread_deleted: Boolean, default false, should the job check that the thread doesn't exist before doing cleanup?
    #                          This is optional as sometimes when we queue the job we know for sure the thread will
    #                          be deleted, but it may not have happened yet.
    def async_delete_all_for_thread(list, thread, ensure_thread_deleted: false)
      newsies_list = List.to_object(list)
      newsies_thread = Thread.to_object(thread)
      DeleteAllForThreadJob.perform_later(newsies_list.type, newsies_list.id, newsies_thread.type, newsies_thread.id, ensure_thread_deleted: ensure_thread_deleted)
    end

    # Public: Ignores the list for the user. See the background job
    # IgnoreListNotificationsJob to call this asynchronously.
    #
    # user - A User.
    # list - A Repository.
    #
    # Returns Newsies::Response instance.
    def ignore_list(user, list)
      if list.nil?
        raise ArgumentError, "list was nil (user: #{user.id})"
      end

      Response.new do
        newsies_list = Newsies::List.to_object(list)

        GitHub.dogstats.time("newsies.ignore_list") do
          ListSubscription.ignore(user.id, newsies_list)
          ThreadTypeSubscription.unsubscribe_from_all_thread_types_for_list(user.id, newsies_list)
          async_notify_list_subscription_state_change(user.id, newsies_list)
          if notifyd_sync_repository_list?(user, list)
            Notifyd::NewsiesService.new.ignore(user: user, list: list)
          end
        end
      end
    end

    # DEPRECATED: Ignores the thread for the user.
    #
    # This method is deprecated. Instead use `.unsubscribe_from_thread` which
    # will always do the "right" thing to ensure the user does not receive
    # notifications for the thread.
    #
    # user - A User.
    # list - A Repository.
    # thread - A Thread (aka Issue, PullRequest, etc.).
    #
    # Returns Newsies::Response instance.
    def ignore_thread(user, list, thread)
      if list.nil?
        raise ArgumentError, "list was nil (user: #{user.id})"
      end

      if thread.nil?
        raise ArgumentError, "thread was nil (user: #{user.id}, list: #{list.id})"
      end

      Response.new do
        GitHub.dogstats.time("newsies.ignore_thread") do
          newsies_list = Newsies::List.to_object(list)
          newsies_thread = Newsies::Thread.to_object(thread, list: newsies_list)
          ThreadSubscription.ignore(user.id, newsies_thread)
        end
      end
    end

    # Public: Checks to see which threads are ignored.
    #
    # user           - A User object.
    # summary_hashes - Array of Summary hashes.
    #
    # Returns a Newsies::Responses::Set of ignored summary id's.
    def ignored(user, summary_hashes)
      threads_by_summary_id = {}
      summary_hashes.each do |summary_hash|
        summary_id = Integer(summary_hash[:id])

        list_type = summary_hash[:list][:type]
        list_id = summary_hash[:list][:id]

        thread_type = summary_hash[:thread][:type]
        thread_id = summary_hash[:thread][:id]

        newsies_list = Newsies::List.new(list_type, list_id)
        newsies_thread = Newsies::Thread.new(thread_type, thread_id, list: newsies_list)

        threads_by_summary_id[summary_id] = newsies_thread
      end

      summary_ids_by_list_key = {}
      threads_by_summary_id.each do |summary_id, newsies_thread|
        summary_ids_by_list_key[newsies_thread.list_key] = summary_id
      end

      newsies_threads = threads_by_summary_id.values
      Responses::Set.new do
        set = Set.new
        subscriptions = ThreadSubscription.ignored(user, newsies_threads)
        subscriptions.each do |subscription|
          if summary_id = summary_ids_by_list_key[subscription.thread.list_key]
            set.add(summary_id)
          end
        end
        set
      end
    end

    # Public: Lists subscriptions that a User has.
    #
    #     # all subscribed and ignored
    #     GitHub.newsies.subscriptions(kyle)
    #
    #     # all ignored
    #     GitHub.newsies.subscriptions(kyle, set: :ignored)
    #
    #     # all subscribed
    #     GitHub.newsies.subscriptions(kyle, set: :subscribed)
    #
    # user      - A User.
    # set       - Optional value to specify the set of subscriptions:
    #             :all        - All subscriptions and ignores (default).
    #             :subscribed - All subscriptions.
    #             :ignored    - All ignores.
    # page      - An optional Integer for which page to return.
    # per_page  - An optional Integer for how many results to return per page.
    # sort      - An optional String or Symbol direction to sort (:asc, "asc", :desc, "desc").
    #
    # Returns Newsies::Responses::Array of Newsies::Subscription instances.
    def subscriptions(user, set: nil, page: nil, per_page: nil, sort: nil, list_type: "Repository")
      Responses::Array.new do
        ListSubscription.subscriptions(
          user.id,
          list_type: list_type,
          set: set,
          page: page,
          per_page: per_page,
          sort: sort,
        )
      end
    end

    # Public: Returns subscriptions for a given user using cursor-based pagination.
    #
    # user    - A User.
    # options - Optional Hash. See ListSubscription#subscriptions_by_cursor
    #           for the supported options.
    def subscriptions_by_cursor(user, options = {})
      Responses::Array.new do
        ListSubscription.subscriptions_by_cursor(user.id, options)
      end
    end

    # Public: Returns a page of thread subscriptions for a given user.
    #
    # user_id         - Database ID of user.
    # cursor          - Integer ID value that marks the start of the page to return. If omitted,
    #                   the returned page will begin with the most recently created subscription.
    # direction       - A Symbol (either :asc or :desc) describing the direction of pagination.
    # limit           - Integer describing the number of items to include in the page.
    # reason          - A subscription reason to which results should be restricted.
    # include_ignored - A Boolean for whether or not to include rows with `ignored=true`.
    # list_type       - An optional string list type. Required if list_id is specified.
    # list_id         - An optional string list id.
    #
    # Returns a Newsies::Responses::Array.
    def thread_subscriptions_by_cursor(
        user_id:,
        cursor: nil,
        direction: :desc,
        limit: 20,
        reason: "manual",
        include_ignored: false,
        list_type: nil,
        list_id: nil
    )
      Responses::PageWithPreviousAndNextFlags.new do
        GitHub.dogstats.time("newsies.thread_subscriptions_by_cursor") do
          scope = ThreadSubscription
            .for_user(user_id)
            .cursor_paginate(
              cursor: cursor,
              direction: direction,
              limit: limit,
              reveal_next_page: true,
              reveal_previous_page: true,
            )

          scope = scope.for_reason(reason) if reason
          scope = scope.excluding_ignored unless include_ignored
          if list_type
            scope = scope.where(list_type: list_type)
            scope = scope.where(list_id: list_id) if list_id
          end
          scope = scope.force_index
          page = scope.to_a

          has_previous_page = false
          if cursor && page.first&.id == cursor
            has_previous_page = true
            page = page.drop(1)
          end

          has_next_page = false
          if page.length > limit
            has_next_page = true
            page = page.take(limit)
          end

          PageWithPreviousAndNextFlags.new(
            page: page,
            has_next_page: has_next_page,
            has_previous_page: has_previous_page,
          )
        end
      end
    end

    def count_thread_subscriptions(user_id:, reason: "manual", include_ignored: false, list_type: nil, list_id: nil, count_limit: 1001)
      Responses::Count.new do
        start_time = GitHub::Dogstats.monotonic_time

        scope = ThreadSubscription
          .for_user(user_id)
          .order(id: :asc)

        scope = scope.for_reason(reason) if reason
        scope = scope.excluding_ignored unless include_ignored
        if list_type
          scope = scope.where(list_type: list_type)
          scope = scope.where(list_id: list_id) if list_id
        end

        scope = scope.force_index

        above_limit = count_limit && scope.offset(count_limit).exists?

        result = ApproximateCount.new(
          above_limit ? count_limit : scope.count,
          accurate: !above_limit)

        GitHub.dogstats.timing_since(
          "newsies.count_thread_subscriptions",
          start_time,
          tags: ["above_limit:#{!!above_limit}"])

        result
      end
    end

    # Public: Returns a batch of thread subscription lists for a given user.
    # The returned Array will be tuples of Newsies::List and total counts.
    #
    # user_id         - Database ID of user.
    # include_ignored - Whether or not to include ignored subscriptions in the
    #                   result.
    # list_type       - An optional string list type.
    #
    # Returns a Newsies::Response.
    def thread_subscription_lists(user_id:, include_ignored: false, list_type: nil)
      Responses::Array.new do
        GitHub.dogstats.time("newsies.thread_subscription_lists") do
          scope = ThreadSubscription
            .for_user(user_id)
            .group(:list_id, :list_type)

          scope = scope.excluding_ignored unless include_ignored
          scope = scope.where(list_type: list_type) if list_type

          scope.size.to_a.map do |(list_id, list_type), count|
            [Newsies::List.new(list_type, list_id), count]
          end
        end
      end
    end

    # Public: Wrapper for subscriptions that returns array of repositories as
    # the response value instead of array of subscriptions. Also does some
    # cleanup for subscriptions where the repository doesn't exist, has been
    # marked deleted or the user does not have permission to.
    #
    # user             - A User.
    # set              - Optional value to specify the set of subscriptions:
    #                      :all            - All list subscriptions and ignores (default).
    #                      :subscribed     - All list subscriptions.
    #                      :ignored        - All ignores.
    # page             - An optional Integer for which page to return.
    # per_page         - An optional Integer for how many results to return per page.
    # excluding        - An optional Array of list_ids to be excluded on the MySQL side.
    # sort             - An optional String or Symbol direction to sort (:asc, "asc", :desc, "desc").
    #
    # Returns Newsies::Responses::Array of Repository instances.
    def subscribed_repositories(user, set: nil, page: nil, per_page: nil, excluding: nil, sort: nil)
      Responses::Array.new do
        good = []
        bad_ids = Set.new
        excluding_lists = Array(excluding).map { |id| Newsies::List.new(::Repository.name, id) }

        begin
          subscriptions = ListSubscription.subscriptions(
                            user.id,
                            set: set,
                            page: page,
                            per_page: per_page,
                            excluding: excluding_lists,
                            sort: sort,
                            list_type: ::Repository.name,
                          )

          # FIXME: this repair likely should be some sort of automated task or
          # a layer up higher as the newsies service shouldn't know this much
          # about repositories
          repository_ids = subscriptions.map(&:list_id).uniq
          repositories = ::Repository.includes(:owner).where(id: repository_ids)
          repositories_by_id = repositories.index_by(&:id)

          private_repository_ids = repositories.reject(&:public?).map(&:id)
          visible_repo_ids = Set.new(user.associated_repository_ids(include_oauth_restriction: false, repository_ids: private_repository_ids))

          subscriptions.each do |subscription|
            repo = repositories_by_id[subscription.list_id]

            if repo.nil? || repo.deleted?
              bad_ids << subscription.list_id
              next
            end

            if repo.public? || visible_repo_ids.include?(repo.id)
              good << repo
            else
              bad_ids << subscription.list_id
            end
          end
        ensure
          if bad_ids.present?
            CleanupListNotificationsJob.perform_later(user.id, ::Repository.name, bad_ids.to_a)
            GitHub.dogstats.count(
              "newsies.cleanup.inaccessible_lists",
              bad_ids.length,
              tags: ["method:subscribed_repositories"],
            )
          end
        end

        good
      end
    end

    # Public: Count a User's subscriptions.
    #
    #     # all subscribed and ignored
    #     GitHub.newsies.count_subscriptions(kyle)
    #
    #     # all ignored
    #     GitHub.newsies.count_subscriptions(kyle, set: :ignored)
    #
    #     # all subscribed
    #     GitHub.newsies.count_subscriptions(kyle, set: :subscribed)
    #
    # user - A User.
    # set  - Optional value to specify the set of subscriptions:
    #        :all        - All subscriptions and ignores (default).
    #        :subscribed - All subscriptions.
    #        :ignored    - All ignores.
    # excluding - An Array of id's to exclude.
    # list_type - String that matches the excluded list id's type. Defaults to
    #             "Repository" for backwards compatibility.
    #
    # Returns a Newsies::Responses::Count instance.
    def count_subscriptions(user, set: nil, excluding: nil, list_type: "Repository")
      raise ArgumentError, "list_type must be present" unless list_type.present?

      Responses::Count.new do
        if excluding
          excluding = excluding.map { |id| Newsies::List.new(list_type, id) }
        end
        ListSubscription.count_subscriptions(user.id, list_type: list_type, set: set, excluding: excluding)
      end
    end

    # Public: List Subscribers for a List.
    #
    # list    - A List.
    # options - An optional or Hash.
    #           :page - Integer page number.  Default: 1
    #
    # Returns a Newsies::Responses::Array instance.
    def subscribers(list, options = {})
      Responses::Array.new do
        newsies_list = Newsies::List.to_object(list)
        subscribers = ListSubscription.subscribers(newsies_list, options)
        user_ids = subscribers.map { |sub| sub.user_id.to_i }
        users = users_by_ids(user_ids).index_by { |u| u.id }
        found = []

        cleaned_up = 0

        user_ids.each do |user_id|
          if user = users[user_id]
            found << user
          else
            # If user doesn't exist, cleanup their subscriptions
            Notifications::Subscriptions.async_delete_user_subscriptions(user_id)
            cleaned_up += 1
          end
        end

        GitHub.dogstats.count("newsies.cleanup.deleted_users", cleaned_up, tags: ["method:subscribers"]) if cleaned_up > 0
        found
      end
    end

    # Public: Filter user_ids that are ignoring an Entity.
    #
    # list - A Repository or Team
    #
    # Returns a Newsies::Responses::Array instance.
    def user_ids_ignoring_list(list)
      newsies_list = Newsies::List.to_object(list)
      Responses::Array.new do
        ListSubscription.for_list(newsies_list).only_ignored.pluck(:user_id)
      end
    end

    def subscriber_ids_by_cursor(list, options = {})
      newsies_list = Newsies::List.to_object(list)
      Responses::Array.new do
        subscribers = ListSubscription.subscribers_by_cursor(newsies_list, options)
        subscribers.map { |subscriber| subscriber.user_id.to_i }
      end
    end

    # Public: Count users subscribing to an Entity.
    #
    # list - A Repository or Team
    #
    # Returns a Newsies::Responses::Count instance.
    def count_subscribers(list, options = {})
      Responses::Count.new do
        newsies_list = Newsies::List.to_object(list)
        ListSubscription.count(newsies_list, options[:exclude_spammy_users])
      end
    end

    # Internal: Initializes a Newsies::SubscriberSet for the notification delivery.
    #
    # list   - A List (Repository, Team, etc.).
    # thread - A Thread (Issue, Commit, DiscussionPost, etc.)
    #
    # Returns a Newsies::Response wrapping a Newsies::SubscriberSet or Newsies::EmptySubscriberSet
    # in case it failed due to underlying storage unavailability
    def subscriber_set_for(list:, thread: nil, explicit_subscribers: nil)
      Response.new(Newsies::EmptySubscriberSet.instance) do
        newsies_list = Newsies::List.to_object(list)
        newsies_thread = if thread
          Newsies::Thread.to_object(thread, list: newsies_list)
        end

        Newsies::SubscriberSet.new(
          list: newsies_list,
          thread: newsies_thread,
          explicit_subscribers: explicit_subscribers)
      end
    end

    # Public: Lists subscribers for a list.
    #
    # list   - A Repository or a Team.
    # thread - Optional thread (Issue, Discussion, or Commit)
    #
    # Yields a Newsies::Subscriber.
    # Returns Newsies::Response.
    def each_subscriber(list, thread = nil, comment = nil, &block)
      Response.new { subscribers_with_preloaded_settings(list, thread).value!.each(&block) }
    end

    # Public: Load default settings for a user.
    #
    # user - A User object
    #
    # Returns a Newsies::Settings
    def default_user_settings(user)
      Newsies::Settings.new(user.id).tap do |settings|
        delivery_type = default_user_notification_delivery_type(user)
        settings.participating_settings.replace delivery_type
        settings.subscribed_settings.replace delivery_type
        if delivery_type.include?(Newsies::HANDLER_WEB)
          settings.vulnerability_web = true
          settings.continuous_integration_web = true
        end
        settings.auto_subscribe = user.created_at < DEFAULT_AUTO_SUBSCRIBE_CUTOFF_DATE
        settings.email(:global, user.default_notification_email)
        settings.user = user
      end
    end

    # Public
    def handler_keys
      handlers.map { |h| h.handler_key }
    end

    # Public: Loads the Thread object for the given Repository.
    #
    # repository - A Repository.
    # klass      - String class name for the Thread.
    # id         - String or Integer ID of the Thread.
    # actor      - User trying to load the thread.
    #
    # Returns a Thread object (Issue, Discussion, or Commit).
    def thread(repository, klass, id, actor:)
      return unless repository
      case klass.to_s
      when /issue/i
        repository.issues.find_by_id(id.to_i)
      when /commit/i
        begin
          return if !repository.commits.exist?(id)
        rescue RepositoryObjectsCollection::InvalidObjectId
          return
        end
        repository.commits.find(id)
      when /discussion/i
        repository.discussions.find_by_id(id)
      end
    end

    # Public: Find all subscribed threads for the given User and Repository.
    #
    # user  - A User.
    # lists - An Array of lists.
    # thread_type - String class name for the Thread.
    #
    # Returns an Newsies::Response::Array instance
    def subscribed_threads(user, lists, thread_type)
      Responses::Array.new do
        newsies_lists = Newsies::List.to_objects(Array(lists))
        ThreadSubscription.subscribed_threads(user.id, newsies_lists, thread_type)
      end
    end

    # Public: Get the email address that emails should go to
    # for a given user and organization.
    #
    # user - a User
    # org  - an Organization or nil
    #
    # Returns a Newsies::Response instance
    #   If an org is passed and the user has specified an email
    #   address for that org, it will be returned. Otherwise the
    #   user's default/primary email address is returned.
    def email(user, org = nil)
      Newsies::Response.new do
        org = nil unless org.is_a?(Organization)
        settings(user).value!.email(org || :global).address
      end
    end

    def token(action, user, id, extra_data = {})
      Newsies::Authentication.token(action, user, id, extra_data)
    end

    def user_and_id_from_token(type, token)
      Newsies::Authentication.user_and_id_from_token(type, token)
    end

    def valid_unsubscribe_token?(token, user, repository)
      Newsies::Authentication.valid_unsubscribe_token?(token, user, repository)
    end

    # Takes a symbol from Newsies::Service#valid_reason_from and makes
    # it fit into a sentence lead with "because ______". Used to give people
    # a reason they subscribed to something in plain ol English.
    def reason_in_words(reason, email: false)
      case reason
      when "comment"                  then "you commented"
      when "author"                   then "you authored the thread"
      when "mention"                  then "you were mentioned"
      when "team_mention"             then "#{reference_individual(email)} on a team that was mentioned"
      when "assign"                   then "you were assigned"
      when "review_requested"         then "your review was requested"
      when "state_change"             then "you modified the open/close state"
      when "security_alert"           then "you have alerting access"
      when "ci_activity"              then "this workflow ran on your branch"
      when "security_advisory_credit" then "you were given credit for contributing to a Security Advisory"
      when "approval_requested"       then "your approval was requested for deployment"
      else "#{reference_individual(email)} subscribed to this thread" # manual, catch-all
      end
    end

    # Public: Do a bulk load of Settings for a list of IDs.
    #
    # user_ids - Array of Integer User IDs.
    #
    # Returns a Newsies::Responses::Array instance.
    def load_user_settings(user_ids)
      users = users_by_ids(user_ids)

      Newsies::Responses::Array.new do
        user_ids = users.map { |u| u.id }

        settings = @settings_store.get_all(*user_ids).
          reject { |settings| settings.new? }.
          index_by { |u| u.id }

        users.map do |user|
          setting = settings[user.id] || default_user_settings(user)
          setting.user = user
          setting
        end
      end
    end

    def bulk_loaded_subscribers(subscribers)
      return Responses::Array.new if subscribers.blank?

      Responses::Array.new do
        user_ids = subscribers.map { |s| s.user_id.to_i }
        settings = load_user_settings(user_ids).value!.index_by { |s| s.id }

        subscribers.each do |sub|
          subscriber_settings = settings[sub.user_id]
          sub.settings = subscriber_settings
          sub.user = subscriber_settings&.user
        end
      end
    end

    def inspect
      "<#%s:%d>" % [self.class, object_id]
    end

    # List subscribers for a list and preloads their notification settings.
    #
    # list                  - A Repository or a Team.
    # thread                - Optional thread (Issue, Commit, DiscussionPost, etc.)
    # explicit_subscribers  - Optional list of users to be subscribed, that
    #                         overwrite the stored subscriptions
    #
    # Returns a Newsies::Responses::Array with Newsies::Subscriber objects.
    def subscribers_with_preloaded_settings(list, thread = nil, explicit_subscribers = nil)
      subscriber_set = subscriber_set_for(
        list: list,
        thread: thread,
        explicit_subscribers: explicit_subscribers,
      ).value!
      bulk_loaded_subscribers(subscriber_set.subscribers)
    end

    # Enqueues a background job that will update the spam status of all notifications
    # related to the given thread
    #
    # list    - A list object e.g. a Repository, Team, etc.
    # thread  - A thread object e.g an Issue, Commit, DiscussionPost, etc.
    def async_update_notifications_spam_status(list, thread)
      newsies_list = List.to_object(list)
      newsies_thread = Thread.to_object(thread)

      UpdateNotificationsSpamStatusJob.perform_later(newsies_list.type, newsies_list.id, newsies_thread.type, newsies_thread.id)
    end

    # Enqueues a background job that will cleanup notifications for a thread which has been
    # found to be inaccessible by a user
    #
    # user_id     - Integer User ID that the thread was found to be inaccessible for
    # list_type   - String class name of the list the inaccessible thread is in (e.g. "Repository")
    # list_id     - String/Integer id of the list the inaccessible thread is in
    # thread_type - String class name of the inaccessible thread (e.g. "Issue")
    # thread_type - String/Integer thread id of the inaccessible thread
    def async_cleanup_inaccessible_thread_for_user(user_id, list_type, list_id, thread_type, thread_id)
      CleanupInaccessibleThreadForUserJob.perform_later(user_id, list_type, list_id, thread_type, thread_id)
    end

    def locator
      ::Newsies::Locator
    end

    private

    # Internal: default handlers for a user
    def default_user_notification_delivery_type(user)
      if enable_default_web_notifications?(user)
        [Newsies::HANDLER_EMAIL, Newsies::HANDLER_WEB]
      elsif user.recently_created?(DEFAULT_EMAIL_ONLY_NOTIFICATIONS_CUTOFF_DATE)
        [Newsies::HANDLER_EMAIL]
      else
        [Newsies::HANDLER_EMAIL, Newsies::HANDLER_WEB]
      end
    end

    # This function verifies if users should have web notifications enabled
    # by default in settings. This is for an experiment started in June 2022 to check
    # if it increases engagement with web notifications
    def enable_default_web_notifications?(user)
      user.recently_created?(DEFAULT_EMAIL_WEB_NOTIFICATIONS_CUTOFF_DATE)
    end

    # Internal: Get a real User from a User or Settings object.
    def real_user(user_or_settings)
      if user_or_settings.is_a?(User)
        user_or_settings
      else
        user_or_settings.user
      end
    end

    # Determines if the reason should overwrite existing reasons.
    #
    # reason - Symbol reason from #valid_reason_from.
    #
    # Returns a Boolean.
    def forced_reason?(reason)
      !Newsies::Reasons::LowPriority.include?(reason)
    end

    # Internal: This function identifies if a notification is being sent through
    # the UI or through an email, and changes the way a person is addressed.
    # Apparently, sending email bodies with apostrophes ruins everything.
    #
    # Returns a String.
    def reference_individual(email)
      email ? "you are" : "you’re"
    end

    def users_by_ids(ids)
      User.includes(:primary_user_email).where(id: ids)
    end

    def async_notify_list_subscription_state_change(user_id, newsies_list)
      Newsies::NotifyListSubscriptionStatusChangeJob.perform_later(user_id, newsies_list.type, newsies_list.id)
    end

    def notifyd_sync_repository_list?(user, list)
      list.is_a?(Repository) && GitHub.flipper[:notifyd_sync_respository_list].enabled?(user)
    end
  end
end
