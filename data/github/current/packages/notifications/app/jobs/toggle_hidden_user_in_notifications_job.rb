# typed: true
# frozen_string_literal: true

# Public: Marks or unmarks a user as hidden (spammy or suspended) in the notifications
# database (on the hidden_users table). Acquires a distributed lock (30-minute timeout,
# keyed by user ID) and calls Newsies::HiddenUser.hide_user/unhide_user within a
# write-throttled context.
#
# Enqueued by: Suspension::SuspensionDependency when a user is suspended or unsuspended,
# and from UpdateTableUserHiddenJob when a user's hidden status changes for spam reasons.
class ToggleHiddenUserInNotificationsJob < ApplicationJob
  queue_as :entries_maintenance

  retry_on GitHub::Restraint::UnableToLock

  retry_on_dirty_exit

  use_replicas ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2

  def perform(user_id, mode)
    restraint.lock!("toggle_hidden_user_in_notifications_for_user_#{user_id}", 1, 30.minutes) do
      Newsies::HiddenUser.throttle do
        if mode == "hide"
          with_write { Newsies::HiddenUser.hide_user(user_id) }
        else
          with_write { Newsies::HiddenUser.unhide_user(user_id) }
        end
      end
    end
  end

  private

  def restraint
    @restraint ||= GitHub::Restraint.new
  end
end
