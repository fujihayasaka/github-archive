# typed: true
# frozen_string_literal: true

class SpammyOrgCheckJob < ApplicationJob
  queue_as :spammy_org_check

  discard_on ActiveJob::DeserializationError

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  def perform(org)
    return unless org.spammy?

    global_notice = with_write { GlobalNoticeNext.new(viewer: org.owner).set_notice(:spammy_orgs) }

    org.admins.each do |admin|
      global_notice = GlobalNoticeNext.new(viewer: admin)
      with_write { global_notice.set_notice(:spammy_orgs) }
    end
  end
end
