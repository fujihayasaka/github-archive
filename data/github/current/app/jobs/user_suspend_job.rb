# typed: false
# frozen_string_literal: true

class UserSuspendJob < ApplicationJob
  queue_as :user_suspend

  def perform(user_id, reason)
    return unless user = User.find_by(id: user_id)
    with_write { user.suspend(reason) }
  end
end
