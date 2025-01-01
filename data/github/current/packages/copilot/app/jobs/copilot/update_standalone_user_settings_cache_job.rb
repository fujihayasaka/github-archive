# typed: strict
# frozen_string_literal: true

class Copilot::UpdateStandaloneUserSettingsCacheJob < CopilotJob
  queue_as :copilot_update_standalone_settings
  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  resolve_tenant_context do |business_id|
    ::Business.find_by(id: business_id)
  end


  # this job enqueues member updates in batches of BATCH_SIZE to parallelize writes
  sig { params(business_id: Integer, start: Integer, finish: Integer).void }
  def perform(business_id, start, finish)
    business = Business.find_by(id: business_id)
    return unless business && Copilot::Business.new(business).copilot_standalone?
    Copilot::Seat.includes(:seat_assignment).where(copilot_seat_assignments: { owner_type: "Business", owner_id: business_id })
      .find_each(start: start, finish: finish) do |seat|
      user = seat.assigned_user
      if user
        with_write do
          Copilot::User.new(T.must(seat.assigned_user)).create_copilot_settings_cache(Copilot::Public::User::CURRENT_VERSION)
        end
      end
    end
  end
end
