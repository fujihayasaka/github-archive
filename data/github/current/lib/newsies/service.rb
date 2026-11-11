# typed: true
# frozen_string_literal: true

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
    trace_method :subscribe_to_thread
    trace_method :subscribe_all_to_thread
    trace_method :subscribe_to_list
    trace_method :subscribe_to_thread_types
    trace_method :unsubscribe
    trace_method :delete_thread_subscriptions
    trace_method :ignore_list
    trace_method :ignored

    attr_reader :handlers, :web

    if Rails.env.test?
      # Needed temporarily for low level unit tests
      attr_reader :list_subs, :thread_subs
    end

    DEFAULT_EMAIL_ONLY_NOTIFICATIONS_CUTOFF_DATE = Time.utc(2016, 01, 07).freeze
    DEFAULT_EMAIL_WEB_NOTIFICATIONS_CUTOFF_DATE = Time.utc(2022, 06, 10).freeze
    DISABLE_DEFAULT_EMAIL_WEB_NOTIFICATIONS_CUTOFF_DATE = Time.utc(2026, 05, 20).freeze
    MAX_REPOSITORY_SUBSCRIPTIONS_PER_USER = 10_000

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
    # is_update               - Boolean indicating whether this notification is due to an update event.
    # spam_check_delay_served - Boolean indicating whether the spam check delay has already been served.
    #
    # Returns nothing.
    def trigger(object, event_time:, recipient_ids: nil, reason: nil, is_update: false, spam_check_delay_served: false)
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
        GitHub.dogstats.distribution_time("newsies.thread_subscribe") do
          next false unless user&.newsies_enabled?
          next false if list.is_a?(Repository) && Notifications::Subscriptions.repository_muted?(user, list)

          unless list.try(:readable_by?, user)
            GitHub.dogstats.increment(
              "newsies.delivery.user_not_subscribable",
              tags: ["class:#{Newsies::Thread.to_type(thread).underscore}"])
          end

          options = ThreadSubscribeOptions.from(reason)
          options.reason = reason_sym = valid_reason_from(options.reason)
          options.force = forced_reason?(reason_sym) unless reason.is_a?(Hash)
          newsies_thread = Newsies::Thread.to_object(thread, list: Newsies::List.to_object(list))
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
        GitHub.dogstats.distribution_time("newsies.thread_subscribe_all") do
          users = users.select { |user| user&.newsies_enabled? }
          user_ids = users.map(&:id)
          muter_ids = Notifications::Subscriptions.repository_muters(user_ids, list.id)
          next nil if muter_ids.nil?

          subscribable_users = users.select do |user|
            next false if muter_ids.include?(user.id)
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
        GitHub.dogstats.distribution_time("newsies.list_subscribe") do
          next false unless user && user.newsies_enabled?

          newsies_list = Newsies::List.to_object(list)
          ListSubscription.subscribe(user.id, newsies_list)
          ThreadTypeSubscription.unsubscribe_from_all_thread_types_for_list(user.id, newsies_list)
          async_notify_list_subscription_state_change(user.id, newsies_list)
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
        GitHub.dogstats.distribution_time("newsies.thread_type_subscribe") do
          next false unless user&.newsies_enabled?
          newsies_list = Newsies::List.to_object(list)

          ListSubscription.unsubscribe(user.id, [newsies_list])
          ThreadTypeSubscription.subscribe_to_thread_types(user.id, newsies_list, thread_types)
          async_notify_list_subscription_state_change(user.id, newsies_list)
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
        GitHub.dogstats.distribution_time("newsies.subscription_status", tags: tags) do
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

    # Public: Checks the subscription status for an array of users and the list.
    #
    # users   - An array of Users.
    # list    - A list (Repository or Team).
    #
    # Returns Newsies::Responses::Array instance wrapping an array of Subscription
    def subscription_status_all(users, list)
      Responses::Array.new do
        statuses = []
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
        statuses
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
        GitHub.dogstats.distribution_time("newsies.user_list_subscriptions") do
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
        GitHub.dogstats.distribution_time("newsies.user_thread_subscriptions") do
          Newsies::ThreadSubscription.for_user(user_id).for_threads(threads)
        end
      end
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
        GitHub.dogstats.distribution_time("newsies.user_thread_type_subscriptions") do
          Newsies::ThreadTypeSubscription.for_user(user_id).for_threads(threads)
        end
      end
    end

    # Public: Unsubscribes a User from a List.
    #
    # user - A User.
    # list - An List or Array of List objects of a single type.
    #
    # Returns Newsies::Response instance.
    def unsubscribe(user, list)
      Response.new do
        GitHub.dogstats.distribution_time("newsies.list_unsubscribe") do
          lists = Newsies::List.to_objects(Array(list))
          ListSubscription.unsubscribe(user.id, lists)
          ThreadTypeSubscription
            .unsubscribe_from_all_thread_types_for_multiple_lists(user.id, lists)
          lists.each do |newsies_list|
            async_notify_list_subscription_state_change(user.id, newsies_list)
          end
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
        GitHub.dogstats.distribution_time("newsies.delete_thread_subscriptions") do
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

    sig { params(user_id: Integer, owner_id: Integer, subscription_type: String).void }
    def async_delete_all_for_user_and_repository_owner(user_id, owner_id, subscription_type)
      DeleteAllForUserAndRepositoryOwnerJob.perform_later(user_id, owner_id, subscription_type)
    end

    sig { params(user_id: Integer, subscription_type: String).void }
    def async_delete_for_user_and_all_repositories(user_id, subscription_type)
      DeleteForUserAndAllRepositoriesJob.perform_later(user_id, "Repository", subscription_type)
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
    # restorable_id - The ID of a restorable object. If provided, deleted subscription data will be recorded for
    #   possible later recovery.
    sig { params(list: List, user_ids: T::Array[Integer], restorable_id: T.nilable(Integer)).void }
    def async_delete_all_for_list_and_users(list, user_ids, restorable_id: nil)
      user_ids.each_slice(Newsies::MaintenanceBaseJob::MAX_LIST_SIZE) do |batched_user_ids|
        DeleteAllForListAndUsersJob.perform_later(list.type, list.id, batched_user_ids, restorable_id: restorable_id)
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
    # thread   - A thread (e.g. Issue) to clean up for
    def async_delete_all_for_thread(list, thread)
      newsies_list = List.to_object(list)
      newsies_thread = Thread.to_object(thread)
      DeleteAllForThreadJob.perform_later(newsies_list.type, newsies_list.id, newsies_thread.type, newsies_thread.id)
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

        GitHub.dogstats.distribution_time("newsies.ignore_list") do
          ListSubscription.ignore(user.id, newsies_list)
          ThreadTypeSubscription.unsubscribe_from_all_thread_types_for_list(user.id, newsies_list)
          async_notify_list_subscription_state_change(user.id, newsies_list)
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
        GitHub.dogstats.distribution_time("newsies.thread_subscriptions_by_cursor") do
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
        result = ApproximateCount.new(above_limit ? count_limit : scope.count, accurate: !above_limit)

        GitHub.dogstats.distribution_timing_since("newsies.count_thread_subscriptions", start_time, tags: ["above_limit:#{!!above_limit}"])

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
        GitHub.dogstats.distribution_time("newsies.thread_subscription_lists") do
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

    def subscriber_ids_by_cursor(list, options = {})
      newsies_list = Newsies::List.to_object(list)
      Responses::Array.new do
        subscribers = ListSubscription.subscribers_by_cursor(newsies_list, options)
        subscribers.map { |subscriber| subscriber.user_id.to_i }
      end
    end

    # Public: Count users subscribing to an Entity.
    #
    # list - A Newsies::List.
    #
    # Returns a Newsies::Responses::Count instance.
    sig { params(list: Newsies::List, options: T::Hash[Symbol, T.untyped]).returns(Responses::Count) }
    def count_subscribers(list, options = {})
      Responses::Count.new do
        exclude_spammy = options[:exclude_spammy_users]
        result = GitHub.dogstats.distribution_time(
          "newsies.count_subscribers",
          tags: ["exclude_spammy:#{!!exclude_spammy}"]
        ) do
          ListSubscription.count(list, exclude_spammy)
        end
        GitHub.dogstats.distribution("newsies.count_subscribers.count", result)
        result
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
        repository.issues.find_by_id(id.to_i) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
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

    # Records an event in hydro for a :link_click token
    #
    # user  - the currently logged in user, clicks will not be linked if token is not for this user
    # token - a Newsies::Authentication token for a user, with the action :link_click
    #         the extra_data on the token should include `reason`
    def track_email_link_click(user, token, tracking_data = {})
      Newsies::Response.new do
        next unless user && FeatureFlag.vexi.enabled?(:notification_email_click_tracking, user, default: false)

        token_user, comment_global_id, token_data = GitHub.newsies.user_and_id_from_token(:link_click, token)
        extra_data = tracking_data.present? ? tracking_data : token_data

        begin
          comment = GlobalID::Locator.locate(comment_global_id)
        rescue => e
          GitHub.logger.error(
            "Error tracking newsies email click for user",
            { user_id: user.id, data: extra_data, error: e.message }
          )
          comment = nil
        end

        unless token_user && comment
          GitHub.dogstats.increment("newsies.link_click_tracking.failed", tags: ["reason:invalid_token"])
          next
        end

        # Don't log actions taken by users who are not the user who signed the token
        unless user == token_user
          GitHub.dogstats.increment("newsies.link_click_tracking.failed", tags: ["reason:incorrect_user"])
          next
        end

        newsies_list = Newsies::List.to_object(comment.notifications_list)
        newsies_thread = Newsies::Thread.to_object(comment.notifications_thread)
        newsies_comment = Newsies::Comment.to_object(comment)

        GlobalInstrumenter.instrument(
          "notifications.user_action",
          user: token_user,
          list_type: newsies_list&.type,
          list_id: newsies_list&.id,
          thread_type: newsies_thread&.type,
          thread_id: newsies_thread&.id,
          comment_type: newsies_comment&.type,
          comment_id: newsies_comment&.id,
          reason: extra_data && (extra_data["reason"] || extra_data[:reason]),
          handler: :EMAIL,
          action: :LINK_CLICK,
          metadata: {
            "event" => extra_data["event"] || extra_data[:event],
            "service" => "newsies",
            "is_pull_request" => (comment.notifications_thread.try(:pull_request_id).present?).to_s
          }
        )
      end
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

    def inspect
      "<#%s:%d>" % [self.class, object_id]
    end

    # Enqueues a background job that will update the spam status of all notifications
    # related to the given thread
    #
    # list    - A list object e.g. a Repository, Team, etc.
    # thread  - A thread object e.g an Issue, Commit, etc.
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

    # Internal: Load default settings for a user.
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
        settings.email(:global, user.default_notification_email)
        settings.user = user
      end
    end

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
      # Disable web notifications enabled by default for users created after 2026-05-20,
      # For more details, see: https://github.com/github/notifications/discussions/6840#discussioncomment-16292559
      return false if user.recently_created?(DISABLE_DEFAULT_EMAIL_WEB_NOTIFICATIONS_CUTOFF_DATE)
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
  end
end
