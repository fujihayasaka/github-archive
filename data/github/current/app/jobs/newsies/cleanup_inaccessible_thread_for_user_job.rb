# typed: false
# frozen_string_literal: true

module Newsies
  # This job cleans up notification entries for a thread that is found to be
  # inaccessible to a user

  # It should be queued when a thread is found to be inaccessible by a user.
  # It will do it's best to figure out _why_ the thread is inaccessible
  # and cleanup as many other related notifications as it can
  class CleanupInaccessibleThreadForUserJob < MaintenanceBaseJob
    class ListMissingError < StandardError; end
    class ListSpammyError < StandardError; end
    class ListNotReadableError < StandardError; end

    class ThreadMissingError < StandardError; end
    class ThreadSpammyError < StandardError; end
    class ThreadNotReadableError < StandardError; end

    class UserMissingError < StandardError; end

    attr_reader :user, :newsies_list, :newsies_thread

    def perform(user_id, list_type, list_id, thread_type, thread_id)
      @user = User.find_by_id(user_id)
      @newsies_list = Newsies::List.new(list_type, list_id)
      @newsies_thread = Newsies::Thread.new(thread_type, thread_id, list: @newsies_list)

      # If the list does not exist any more,
      # delete all notifications for the list for everybody
      unless list
        report_error(ListMissingError)
        subject = Notifications::Subject.new(type: newsies_list.type, id: newsies_list.id)
        return Notifications::Subscriptions.async_delete_list_subscriptions(subject)
      end

      # If the list is spammy,
      # leave notifications alone for now
      if list.try(:spammy?)
        report_error(ListSpammyError)
        return
      end

      # If somehow the user does not exist,
      # delete all their notifications
      unless user
        report_error(UserMissingError)
        return Notifications::Subscriptions.async_delete_user_subscriptions(user_id)
      end

      # If the list is not readable by the current user,
      # delete all notifications for the list for the current user
      unless list.readable_by?(user)
        report_error(ListNotReadableError)
        return Notifications::Subscriptions.async_delete_user_subscriptions_for_lists(
          user_id: user_id,
          lists: [Notifications::Subject.new(type: newsies_list.type, id: newsies_list.id)],
        )
      end

      # If the thread does not exist any more,
      # delete all notifications for the thread for everybody
      unless thread
        report_error(ThreadMissingError)
        return DeleteAllForThreadJob.perform_later(newsies_list.type, newsies_list.id, newsies_thread.type, newsies_thread.id)
      end

      # If the thread is spammy,
      # leave notifications alone for now
      if thread.try(:spammy?)
        report_error(ThreadSpammyError)
        return
      end

      # If the thread is not readable by the current user,
      # just delete this one notification
      unless thread.readable_by?(user)
        report_error(ThreadNotReadableError)
        trace_attributes = { "gh.user.id" => user.id, "gh.notifications.thread_id" => thread_id, "gh.notifications.thread_type" => thread_type }
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
        newsies_thread.type.constantize.find_by_id(newsies_thread.id)
      end
    end

    def report_error(error_class)
      # Report the same error class, but attach thread type to error message
      error = error_class.new("thread with type #{newsies_thread.type} not readable by viewer")
      data = {
        user: user&.login,
        notifications_list_key: newsies_list.key,
        notifications_thread_key: newsies_thread.key,
      }
      NotificationsFailbot.report!(error, data)
    end
  end
end
