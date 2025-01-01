# typed: strict
# frozen_string_literal: true

class Copilot::BatchUpdateEnterpriseUserSettingsJob < CopilotJob
  queue_as :copilot_update_enterprise_user_settings
  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  resolve_tenant_context do |business|
    business
  end

  # this job enqueues member updates in batches of BATCH_SIZE to parallelize writes
  BATCH_SIZE = 1_000

  sig { params(business: Business).void }
  def perform(business)
    # This entire guard can be removed when the :copilot_business_user_assignment FF is removed.
    return unless Copilot::Business.new(business).copilot_standalone? || business.feature_flag_enabled_or_raise?(:copilot_business_user_assignment) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage

    Copilot::Seat.includes(:seat_assignment).where(copilot_seat_assignments: { owner_type: "Business", owner_id: business.id })
      .find_in_batches(batch_size: BATCH_SIZE) do |batch|
        start = T.let(T.must(batch[0]), Copilot::Seat).id || 0
        finish = T.let(T.must(batch[-1]), Copilot::Seat).id || 0
        Copilot::UpdateEnterpriseUserSettingsCacheJob.perform_later(T.cast(business.id, Integer), start, finish)
      end
  end
end
