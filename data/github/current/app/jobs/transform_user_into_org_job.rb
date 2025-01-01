# typed: true
# frozen_string_literal: true

class TransformUserIntoOrgJob < ApplicationJob
  queue_as :transform_user_into_org

  locked_by timeout: 15.minutes, key: DEFAULT_LOCK_PROC

  retry_on_dirty_exit

  def perform(user_id, owner_id, options = {})
    return unless user  = User.find_by(id: user_id)
    return unless owner = User.find_by(id: owner_id)
    Failbot.push(user.event_context)

    with_write { Organization.transform!(user, owner, options) }
  end
end
