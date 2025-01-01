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
    # Returns Newsies::Response.
    def self.unsubscribe_from_thread(user, thread)
      GitHub.tracer.in_span("unsubscribe_from_thread", kind: :internal) do
        send_to_notifyd = thread&.respond_to?(:unsubscribe_in_notifyd?) && thread&.unsubscribe_in_notifyd?(user)
        notifyd_primary = thread&.respond_to?(:notifyd_primary?) && thread.notifyd_primary?(user)

        newsies_response = handle_errors(raise_errors: !notifyd_primary, response_class: Newsies::Response, method: "unsubscribe_from_thread") do
          GitHub.newsies.unsubscribe_from_thread(user, thread)
        end

        return newsies_response unless send_to_notifyd

        notifyd_response = handle_errors(response_class: Notifyd::Responses::Boolean, method: "unsubscribe_from_thread") do
          notifyd_unsubscribe_from_thread(user, thread)
        end

        # Newsies.unsubscribe_from_thread does not return boolean response, so we can't compare values, instead we compare
        # boolean value of Notifyd response with the indicator of success from Newsies response
        if notifyd_response&.value != newsies_response&.success?
          GitHub.dogstats.increment(DIFFERENCE_STAT, tags: ["method:unsubscribe_from_thread"])
          GitHub.logger.info("found differences in results between notifyd and newsies", {
            "code.namespace" => "Notifications::Subscriptions",
            "code.function" => "unsubscribe_from_thread",
            "gh.notifications.response" => newsies_response.nil? ? "" : newsies_response,
            "gh.notifyd.response" => notifyd_response.nil? ? "" : notifyd_response
          })
        end

        notifyd_primary ? notifyd_response : newsies_response
      end
    end

    # Public: Get a subscription status
    #
    # user    - A User.
    # List    - A list (ie: Repository).
    # thread  - A thread (ie: Issue, Commit, etc.).
    #
    # Returns Newsies::Response or Notifyd::Response
    def self.subscription_status(user, list, thread)
      GitHub.tracer.in_span("subscription_status", kind: :internal) do
        if thread.respond_to?(:notifyd_primary?) && thread.notifyd_primary?(user)
          notifyd_subscription_status(user, list, thread)
        else
          GitHub.newsies.subscription_status(user, list, thread)
        end
      end
    end

    # Public: Delete thread subscriptions for provided user
    def self.delete_thread_subscriptions(user_id:, thread_subscription_ids:)
      GitHub.tracer.in_span("delete_thread_subscriptions", kind: :internal) do
        handle_errors(response_class: Newsies::Responses::Boolean, method: "delete_thread_subscriptions") do
          if GitHub.flipper[:notifyd_delete_thread_subscriptions].enabled?(User.new(id: user_id))
            notifyd_schedule_delete_thread_subscriptions(user_id: user_id, thread_subscription_ids: thread_subscription_ids)
            GitHub.newsies.delete_thread_subscriptions(user_id: user_id, thread_subscription_ids: thread_subscription_ids)
          else
            GitHub.newsies.delete_thread_subscriptions(user_id: user_id, thread_subscription_ids: thread_subscription_ids)
          end
        end
      end
    end

    # Public: Unsubscribe a user from a specified lists that do not exist anymore
    #
    # user - user to unsubscribe from lists
    # lists - lists to unsubscribe from
    #
    # The logic of Nofifyd::NewsiesService#unwatch is a bit different from Newsies::ListSubscription#unsubscribe
    # Notifyd call also removes thread type subscriptions that belong to a given list while Newsies' doesn't.
    # It makes sense to remove thread subscriptions as well if list does not exist anymore.
    def self.cleanup_list_subscriptions(user, non_existing_lists, tags)
      GitHub.tracer.in_span("cleanup_list_subscriptions", kind: :internal) do
        Newsies::ListSubscription.unsubscribe(user.id, non_existing_lists)
        GitHub.dogstats.count("newsies.cleanup_list_subscriptions.count", non_existing_lists.length, tags: tags)

        if GitHub.flipper[:notifyd_sync_respository_list].enabled?(user)
          Notifyd::NewsiesService.new.unwatch(user: user, lists: non_existing_lists)
          GitHub.dogstats.count("notifyd.cleanup_list_subscriptions.count", non_existing_lists.length, tags: tags)
        end
      end
    end

    # Public: Unsubscribe a non-existing user from all lists
    # This method works the same way for Newsies subscriptions as cleanup_list_subscriptions and will unsubscribe user
    # from explicitly passed lists. For Notifyd subscriptions it will unsubscribe user from all lists. This is due to differences
    # in Newsies and Notifyd APIs and this wrapper method needs to dispatch to both.
    #
    # id - user_id of a user that has to be unsubscribed
    # lists - lists to unsubscribe from (this parameter is used only by Newsies call)
    # tags - tags to be added to the dogstatsd metric
    #
    # The logic of Nofifyd::NewsiesService#unwatch_all is a bit different from Newsies::ListSubscription#unsubscribe
    # Notifyd call also removes thread type subscriptions that belong to a given list while Newsies' doesn't.
    # It makes sense to remove thread subscriptions as well if a user does not exist anymore.
    def self.cleanup_all_list_subscriptions(non_existing_user_id, lists, tags)
      GitHub.tracer.in_span("cleanup_all_list_subscriptions", kind: :internal) do
        Newsies::ListSubscription.unsubscribe(non_existing_user_id, lists)
        GitHub.dogstats.count("newsies.cleanup_all_list_subscriptions.count", lists.length, tags: tags)

        Notifyd::NewsiesService.new.unwatch_all(user_id: non_existing_user_id, ref_type: "Repository")
        GitHub.dogstats.count("notifyd.cleanup_all_list_subscriptions.count", lists.length, tags: tags)
      end
    end

    def self.unwatch_repositories(user, repositories)
      GitHub.tracer.in_span("unwatch_repositories", kind: :internal) do
        Newsies::ListSubscription.unsubscribe(user.id, repositories)
        GitHub.dogstats.count("newsies.unwatched_repositories.count", repositories.length)

        if GitHub.flipper[:notifyd_sync_respository_list].enabled?(user)
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
      if list.type == "Repository" && GitHub.flipper[:notifyd_maintenance_delete_repository].enabled?(Repository.new(id: list.id))
        Notifyd::MaintenanceService.new.delete_repository(list.id)
        GitHub.dogstats.increment("notifyd.async_delete_list_subscriptions.count")
      end
    end

    # Public: Asynchronously delete list subscriptions for a sequence of users.
    #
    # list - A list Subject (e.g. Repository, Team)
    # user_ids - An array of integer user IDs.
    sig { params(list: Subject, user_ids: T::Array[Integer]).void }
    def self.async_delete_list_subscriptions_for_users(list:, user_ids:)
      # NOTE(abeaumont): Newsies deletes both subscriptions and web notifications,
      # as both actions are coupled in the same job, breaking separation of concerns.
      GitHub.newsies.async_delete_all_for_list_and_users(Newsies::List.new(list.type, list.id), user_ids)
      GitHub.dogstats.count("newsies.async_delete_list_subscriptions_for_users.count", user_ids.length)
      if list.type == "Repository" && GitHub.flipper[:notifyd_maintenance_delete_repository_for_users].enabled?(Repository.new(id: list.id))
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
      if GitHub.flipper[:notifyd_maintenance_delete_user].enabled?(User.new(id: user_id))
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
      if !repo_ids.empty? && GitHub.flipper[:notifyd_maintenance_delete_user_repositories].enabled?(User.new(id: user_id))
        Notifyd::MaintenanceService.new.delete_user_repositories(user_id: user_id, repo_ids: repo_ids)
        GitHub.dogstats.count("notifyd.async_delete_user_subscriptions_for_lists.count", repo_ids.length)
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

    private

    private_class_method def self.handle_errors(raise_errors: false, response_class: nil, method:, &block)
      notify_system = response_class == Notifyd::Responses::Boolean ? "notifyd" : "newsies"
      begin
        yield
      rescue => e # rubocop:todo Lint/GenericRescue
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
