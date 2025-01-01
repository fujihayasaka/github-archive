# typed: strict
# frozen_string_literal: true

class Copilot::UpdateStandaloneUserSettingsCacheJob < CopilotJob
  queue_as :copilot_update_standalone_settings
  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  resolve_tenant_context do |business_id|
    ::Business.find_by(id: business_id)
  end


  # This job loops over all seats for a standalone business and updates the settings cache for
  # each seat's assigned user.
  sig { params(business_id: Integer, start: Integer, finish: Integer).void }
  def perform(business_id, start, finish)
    business = Business.find_by(id: business_id)
    return unless business && Copilot::Business.new(business).copilot_standalone?

    Copilot::Seat.throttle do
      Copilot::Seat.for_owner(business).find_each(start: start, finish: finish) do |seat|
        user = seat.assigned_user

        next unless user

        # Constructing the Copilot::User could result in a configuration getting created,
        # but that code is wrapped in a with_write block, so we don't need one here.
        Copilot::User.new(user).create_copilot_settings_cache(Copilot::Public::User::CURRENT_VERSION)
      end
    end
  end
end
