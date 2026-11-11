# typed: true
# frozen_string_literal: true

module Newsies
  # This job cleans up notification entries for a thread that is found to be
  # inaccessible to a user

  # It should be queued when a thread is found to be inaccessible by a user.
  # It will do it's best to figure out _why_ the thread is inaccessible
  # and cleanup as many other related notifications as it can
  class CleanupInaccessibleThreadForUserJob < MaintenanceBaseJob
    attr_reader :user, :newsies_list, :newsies_thread

    def perform(user_id, list_type, list_id, thread_type, thread_id)
      @user = User.find_by(id: user_id)
      @newsies_list = Newsies::List.new(list_type, list_id)
      @newsies_thread = Newsies::Thread.new(thread_type, thread_id, list: @newsies_list)

      # If the list does not exist any more,
      # delete all notifications for the list for everybody
      unless list
        report(:no_list)
        subject = Notifications::Subject.new(type: newsies_list.type, id: newsies_list.id)
        return Notifications::Subscriptions.async_delete_list_subscriptions(subject)
      end

      # If the list is spammy,
      # leave notifications alone for now
      if list.try(:spammy?)
        report(:spammy_list)
        return
      end

      # If somehow the user does not exist,
      # delete all their notifications
      unless user
        report(:no_user)
        return Notifications::Subscriptions.async_delete_user_subscriptions(user_id)
      end

      # If the list is not readable by the current user,
      # delete all notifications for the list for the current user
      unless list.readable_by?(user)
        report(:unreadable_list)
        return Notifications::Subscriptions.async_delete_user_subscriptions_for_lists(
          user_id: user_id,
          lists: [Notifications::Subject.new(type: newsies_list.type, id: newsies_list.id)],
        )
      end

      # If the thread does not exist any more,
      # delete all notifications for the thread for everybody
      unless thread
        report(:no_thread)
        return DeleteAllForThreadJob.perform_later(newsies_list.type, newsies_list.id, newsies_thread.type, newsies_thread.id)
      end

      # If the thread is spammy,
      # leave notifications alone for now
      if thread.try(:spammy?)
        report(:spammy_thread)
        return
      end

      # If the thread is not readable by the current user,
      # just delete this one notification
      unless thread.readable_by?(user)
        report(:unreadable_thread)
        trace_attributes = { "gh.user.id" => user.id, "gh.notifications.thread.id" => thread_id, "gh.notifications.thread.type" => thread_type }
        GitHub.tracer.in_span("delete_all_notification_entries", kind: :internal, attributes: trace_attributes) do
          with_write do
            Newsies::NotificationEntry.for_user(user.id).for_thread(newsies_thread).delete_all
          end
        end
      end
    end

    private

    def list
      return @list if defined?(@list)
      @list = newsies_list.type.constantize.find_by_id(newsies_list.id)
    end

    def thread
      return @thread if defined?(@thread)

      @thread = if newsies_thread.type == "Grit::Commit"
        begin
          list.commits.find(newsies_thread.id) if list
        rescue GitRPC::InvalidObject, GitRPC::ObjectMissing
          nil
        end
      else
        newsies_thread.type.constantize.find_by_id(newsies_thread.id) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      end
    end

    def report(result)
      GitHub.dogstats.increment("newsies.cleanup_inaccessible_thread_for_user_job", tags: ["thread_type:#{newsies_thread.type}", "result:#{result}"])
      GitHub.logger.info("thread not readable by viewer", {
        "gh.user.id" => user&.id.to_s,
        "gh.notifications.list.type" => newsies_list.type,
        "gh.notifications.list.id" => newsies_list.id,
        "gh.notifications.thread.type" => newsies_thread.type,
        "gh.notifications.thread.id" => newsies_thread.id,
        "gh.notifications.result" => result,
      })
    end
  end
end
