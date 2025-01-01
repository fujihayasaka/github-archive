# typed: true
# frozen_string_literal: true

class CleanupListNotificationsJob < ApplicationJob
  queue_as :kubernetes_notifications

  retry_on_dirty_exit

  BATCH_SIZE = 100

  # Performs permissions checks and unsubscribes a user from notification
  # lists they should no longer be receiving notifications for.
  #
  # user_id   - The user_id to clean up notifications for.
  # list_type - String type of the notifications list class. Supported types
  #             are `Repository` and `Team`.
  # list_ids  - Array of list IDs to query and check permissions against.
  def perform(user_id, list_type, list_ids, options = {})
    return if list_ids.empty?
    return unless user = User.find_by(id: user_id)

    GitHub.tracer.in_span("perform_cleanup_list_notifications_job", kind: :internal, attributes: { "gh.notifications.job.item.count" => list_ids.size }) do
      list_ids.each_slice(BATCH_SIZE) do |slice|
        lists = lists_from(slice, list_type: list_type.constantize)

        to_unsubscribe = lists.select { |list| unsubscribe?(list, user) }.map do |list|
          Notifications::Subject.new(type: list_type, id: list.id)
        end
        GitHub.tracer.in_span("async_delete_user_subscriptions_for_lists", kind: :internal) do
          unless to_unsubscribe.empty?
            Notifications::Subscriptions.async_delete_user_subscriptions_for_lists(user_id: user.id, lists: to_unsubscribe)
          end
        end
      end
    end
  end

  private

  # Internal: Should we execute the `Notifications::Subscriptions.async_delete_user_subscriptions_for_lists` method?
  #
  # Returns a Boolean.
  def unsubscribe?(list, user)
    return true if list.new_record?

    case list
    when Repository
      list.deleted? || !list.pullable_by?(user)
    when Team
      !list.visible_to?(user)
    else
      false
    end
  end

  # Internal: Gets all lists for the given IDs.  If a list has been deleted, construct
  # a new record with that ID so that we can clear the notifications
  # subscriptions.
  #
  # Returns an Array of list objects.
  def lists_from(list_ids, list_type:)
    lists = list_type.where(id: list_ids).index_by(&:id)
    list_ids.map { |id| lists[id] || list_type.new { |r| r.id = id } }
  end
end
