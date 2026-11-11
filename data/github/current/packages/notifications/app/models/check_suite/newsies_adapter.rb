# typed: true
# frozen_string_literal: true

# This module implements methods expected by Newsies.
module CheckSuite::NewsiesAdapter
  extend T::Helpers

  requires_ancestor { CheckSuite }

  # Associates check suite updates with the repo it belongs to so that
  # subsequent updates will refer to the same repo.
  sig { returns Promise[T.nilable(Repository)] }
  def async_notifications_list
    async_repository
  end

  sig { returns T.nilable(Repository) }
  def notifications_list
    async_notifications_list.sync
  end

  # Refer to itself as the thread so that subsequent updates will refer to the
  # same check suite object.
  sig { returns CheckSuite }
  def notifications_thread
    T.bind(self, CheckSuite)
    self
  end

  sig { returns T.nilable(User) }
  def notifications_author
    creator
  end

  # Overrides for Summarizable#get_notification_summary
  def get_notification_summary
    list = Newsies::List.to_object(notifications_list)
    thread = Newsies::List.to_object(notifications_thread)
    GitHub.newsies.web.find_rollup_summary_by_thread(list, thread)
  end

  # Overrides for Summarizable#destroy_notification_summary
  def destroy_notification_summary
    # Do nothing. Archiving of check suites happens well over the lifetime
    # of all the notifications related models, and it generates a vast amount
    # of useless work.
  end

  # Overrides for Summarizable#update_notification_rollup
  def update_notification_rollup(summary)
    summary.summarize_check_suite(self)
  end
end
