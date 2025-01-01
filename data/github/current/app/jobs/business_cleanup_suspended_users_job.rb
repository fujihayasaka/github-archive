# typed: true
# frozen_string_literal: true

class BusinessCleanupSuspendedUsersJob < ApplicationJob
  queue_as :business_cleanup_suspended_users

  retry_on_dirty_exit

  BATCH_SIZE = 100

  resolve_tenant_context do |business|
    business
  end

  def perform(business, actor)
    return unless business.enterprise_managed_user_enabled?
    return unless actor.site_admin?
    ActiveRecord::Base.connected_to(role: :reading) do
      ids = business.suspended_member_ids
      ids.each_slice(BATCH_SIZE) do |this_slice|
        User.where(id: this_slice).includes(:interaction, :most_recent_session).each do |user|
          next if user.most_recent_session.present? || user.interaction&.last_active_at.present? || user.interaction&.last_active_session_at.present?
          with_write do
            begin
              user.async_destroy(actor, skip_permitted_check: true, site_admin_deletion: true)
            rescue ActiveRecord::RecordInvalid => error
              Failbot.report!(error)
            end
          end
        end
      end
    end
    business.update_license_usage
  end
end
