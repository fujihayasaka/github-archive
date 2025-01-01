# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class LargerRunnersOnboardWaitlistUserJob < ApplicationJob
  queue_as :mailers
  retry_on_dirty_exit

  locked_by timeout: 1.hour, key: DEFAULT_LOCK_PROC

  def perform(membership)
    member = membership.member
  end
end
