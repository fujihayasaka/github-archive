# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class UserSuspendDormantJob < ApplicationJob
  queue_as :user_suspend_dormant
  retry_on_dirty_exit

  def perform(threshold)
    User.dormant_users(threshold: threshold).each do |u|
      UserSuspendJob.perform_later(u.id, "Bulk dormant user suspension")
    end
  end
end
