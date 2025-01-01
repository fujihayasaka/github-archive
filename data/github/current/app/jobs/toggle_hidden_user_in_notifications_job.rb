# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

# Public: Marks a spammy user as spammy in the notifications database.
class ToggleHiddenUserInNotificationsJob < ApplicationJob
  queue_as :toggle_hidden_user_in_notifications

  retry_on GitHub::Restraint::UnableToLock

  retry_on_dirty_exit

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
