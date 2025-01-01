# typed: true
# frozen_string_literal: true

# Whenever an issue's metadata is updated, we need to notify all of the issues that are tracking it.
class NotifyTrackedByJob < ApplicationJob
  extend T::Sig

  queue_as :notify_tracked_by

  sig { params(tracked_by_ids: T::Array[Integer]).void }
  def perform(tracked_by_ids)
    issues = ::Issue.where(id: tracked_by_ids)
    issues.each(&:notify_socket_subscribers)
  end
end
