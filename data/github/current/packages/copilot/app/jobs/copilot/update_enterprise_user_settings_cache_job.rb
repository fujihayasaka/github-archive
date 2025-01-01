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
    # This entire guard can be removed when the :copilot_business_user_assignment FF is removed.
    return unless business && (Copilot::Business.new(business).copilot_standalone? || business.feature_flag_enabled_or_raise?(:copilot_business_user_assignment)) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage

    Copilot::Seat.throttle do
      Copilot::Seat.for_owner(business).find_each(start: start, finish: finish) do |seat|
        user = seat.assigned_user

        next unless user && business.exclusive_unaffiliated_member?(user)

        # Constructing the Copilot::User could result in a configuration getting created,
        # but that code is wrapped in a with_write block, so we don't need one here.
        Copilot::User.new(user).create_copilot_settings_cache(Copilot::Public::User::CURRENT_VERSION)
      end
    end
  end
end
