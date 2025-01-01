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
end
