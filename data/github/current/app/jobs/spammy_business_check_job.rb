# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class SpammyBusinessCheckJob < ApplicationJob
  queue_as :spammy_business_check

  discard_on ActiveJob::DeserializationError
  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  def perform(business)
    return unless business.spammy?

    business.owners.each do |owner|
      global_notice = GlobalNoticeNext.new(viewer: owner)
      with_write { global_notice.set_notice(:spammy_businesses) }
    end
  end
end
