# typed: true
# frozen_string_literal: true

# Public: Moves all notifications authored by or owned by a user between
# the notification_entries and spammy_notification_entries tables based on the user's spam status.
#
# - When user is marked as spammy: moves from notification_entries → spammy_notification_entries
# - When user is marked as not spammy: moves from spammy_notification_entries → notification_entries
class ToggleNotificationsForSpammyUsersJob < ApplicationJob
  queue_as :toggle_spammy_notifications

  retry_on GitHub::Restraint::UnableToLock

  retry_on_dirty_exit

  # Execute this job with the given user ID.
  #
  # user_id - The Integer ID of the user whose issue notifications should
  # be moved to/from the spammy_notification_entries table.
  #
  def perform(user_id, mode, _opts = {})
    return false unless user = User.find_by(id: user_id)

    Failbot.push({ "gh.user.id": user_id })

    restraint.lock!("toggle_notifications_visibility_for_user_#{user_id}", 1, 30.minutes) do
      move_notification_entries_for_spammy_user(user_id, mode)
    end
  end

  private

  def move_notification_entries_for_spammy_user(user_id, mode)
    source_class = mode == "hide" ? Newsies::NotificationEntry : Newsies::SpammyNotificationEntry
    destination_class = mode == "hide" ? Newsies::SpammyNotificationEntry : Newsies::NotificationEntry

    # Move notification entries authored by this user
    move_entries(source_class, destination_class, source_class.where(author_id: user_id))

    # Move notification entries owned by this user
    move_entries(source_class, destination_class, source_class.where(owner_id: user_id))
  end

  def move_entries(source_class, destination_class, notification_entries)
    notification_entries.in_batches(of: 1000) do |batched_scope|
      columns = (source_class.columns.map(&:name) & destination_class.columns.map(&:name))

      values = batched_scope.select(columns).map(&:attributes)

      ActiveRecord::Base.connected_to(role: :writing) do
        if values.any?
          destination_class.throttle_writes { destination_class.insert_all(values) }
        end

        source_class.throttle_writes { batched_scope.delete_all }
      end
    end
  end

  def restraint
    @restraint ||= GitHub::Restraint.new
  end

end
