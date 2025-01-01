# typed: true
# frozen_string_literal: true

module EnterpriseOnboarding
  class GhasTrialEligibilitySearchJob < BatchedJob
    queue_as :ghas_trial

    schedule interval: 24.hours, condition: -> { !GitHub.enterprise? }

    retry_on ActiveJob::DeserializationError
    retry_on_dirty_exit

    BATCH_SIZE = 500

    def process_batch(batch, *args, **options)
      batch.each do |organization|
        next if organization.advanced_security_eligible_for_entity? && !organization.plan.business?
        next if !organization.advanced_security_eligible_for_entity? && organization.plan.business?

        ::EnterpriseCloudOnboard::GhasTrialEligibilityJob.perform_later(organization)
      end
    end

    private

    def next_batch(*args, timestamp: Time.now.utc, offset_item_id: 0, progress: 0, **options)
      ActiveRecord::Base.connected_to(role: :reading_slow) do
        Organization.
        where(plan: [GitHub::Plan.business_plus.name, GitHub::Plan.business.name]).
        where("id > ?", offset_item_id).
        limit(BATCH_SIZE).
        order(id: :asc)
      end
    end
  end
end
