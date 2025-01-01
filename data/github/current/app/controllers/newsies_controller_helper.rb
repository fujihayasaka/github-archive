# typed: true
# frozen_string_literal: true

# Defines controller helper methods related to displaying Notifications.
module NewsiesControllerHelper
  extend T::Helpers

  abstract!

  sig { abstract.returns(T.nilable(User)) }
  def current_user; end

  sig { abstract.returns(T.nilable(T::Boolean)) }
  def logged_in?; end

  def self.included(base)
    return unless base.respond_to?(:helper_method)
    base.helper_method :mark_thread_as_read
    base.helper_method :async_mark_thread_as_read
  end

  private

  # Public: Marks the thread's notification as 'read' for the current user.
  #
  # thread - A thread (either a Commit or an Issue).
  #
  # Returns nothing.
  def mark_thread_as_read(thread, user: current_user)
    return unless logged_in?

    GitHub.dogstats.increment("notifications.mark_thread_as_read.user_type", tags: ["user_type:#{user.type}", "spammy:#{user.spammy?}", "is_bot:#{user.bot?}"])
    response = GitHub.newsies.web.notification(user, thread.notifications_list, thread)

    if response.success? && response.value&.unread?
      ActiveRecord::Base.connected_to(role: :writing) do
        GitHub.newsies.web.mark_thread_read(user, thread)
      end
    end
  end

  # Public: Marks the thread's notification as 'read' for the current user asynchronously
  #
  # thread - A thread (either a Commit or an Issue).
  #
  # Returns nothing.
  def async_mark_thread_as_read(thread, user: current_user)
    return unless logged_in?

    GitHub.dogstats.increment("notifications.mark_thread_as_read.user_type", tags: ["user_type:#{user.type}", "spammy:#{user.spammy?}", "is_bot:#{user.bot?}"])
    async_mark_threads_as_read [thread], user: user
  end

  # Public: Marks the threads' notifications as 'read' for the current user asynchronously
  #
  # threads - Threads (either Commit, Issue, etc).
  #
  # Returns nothing.
  def async_mark_threads_as_read(threads, user: current_user)
    return unless logged_in?

    # For the moment, in Enterprise environments we always run this action in sync
    if GitHub.enterprise?
      threads.each { |thread| mark_thread_as_read(thread, user: user) }
      return
    end

    gids = threads.filter_map do |thread|
      gid = thread.respond_to?(:to_global_id) ? thread.to_global_id : GitHub.newsies.locator.to_global_id(thread)
      if gid
        gid.to_s
      else
        GitHub.logger.info("Could not generate GlobalID for thread", {
          "code.namespace" => "NewsiesControllerHelper",
          "code.function" => "async_mark_threads_as_read",
          "gh.user.id" => user.id,
          "gh.notifications.thread" => "#{thread.class.name}##{thread.try(:id)}",
        })

        nil
      end
    end

    message = {
      user_id: user.id,
      threads: gids,
    }

    GitHub.hydro_publisher.publish(
      message,
      schema: "notifications.v0.MarkAsRead",
      topic_format_options: { format_version: Hydro::Topic::FormatVersion::V2 },
    )
  end
end
