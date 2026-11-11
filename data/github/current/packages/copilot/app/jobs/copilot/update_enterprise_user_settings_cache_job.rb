# typed: strict
# frozen_string_literal: true

class Copilot::UpdateEnterpriseUserSettingsCacheJob < CopilotJob
  queue_as :copilot_update_enterprise_user_settings
  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  resolve_tenant_context do |business_id|
    ::Business.find_by(id: business_id)
  end

  # This job loops over all seats for a unaffiliated users in a business (all users are unaffiliated in standalone businesses)
  # and updates the settings cache for each seat's assigned user.
  sig { params(business_id: Integer, start: Integer, finish: Integer).void }
  def perform(business_id, start, finish)
    business = Business.find_by(id: business_id)
    return unless business

    Copilot::Seat
    .includes(:assigned_user)
    .for_owner(business)
    .find_each(start: start, finish: finish, batch_size: 100) do |seat|
      user = seat.assigned_user

      next if user.nil?

      next unless business.unaffiliated_member?(user)

      # Constructing the Copilot::User could result in a configuration getting created,
      # but that code is wrapped in a with_write block, so we don't need one here.
      Copilot::User.new(user).create_copilot_settings_cache(
        Copilot::PolicyCacheVersion.current_version,
        throttle: true,
        reason: "update_enterprise_user_settings_cache_job"
      )
    end
  end
end
