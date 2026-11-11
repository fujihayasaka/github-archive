# typed: true
# frozen_string_literal: true

class RemoveExpiredAnnouncementsJob < ApplicationJob
  schedule interval: 4.hours

  queue_as :remove_expired_announcements

  retry_on_dirty_exit

  exempt_from_tenant_context_requirement

  def perform
    with_write do
      EnterpriseBanner.destroy_by("expires_at < ?", Time.now.utc)
    end
  end
end
