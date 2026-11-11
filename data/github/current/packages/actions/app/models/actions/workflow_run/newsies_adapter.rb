# typed: false
# frozen_string_literal: true

# This module implements methods expected by Newsies.
module Actions::WorkflowRun::NewsiesAdapter
  # Associates workflow run updates with the repo it belongs to so that
  # subsequent updates will refer to the same repo.
  def async_notifications_list
    async_repository
  end

  def notifications_list
    async_notifications_list.sync
  end

  # Refer to itself as the thread so that subsequent updates will refer to the
  # same workflow run object.
  def notifications_thread
    self
  end

  def notifications_author
    creator
  end
end
