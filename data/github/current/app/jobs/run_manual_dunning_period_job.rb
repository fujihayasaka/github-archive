# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class RunManualDunningPeriodJob < BillingJob
  locked_by timeout: 5.minutes, key: ActiveJob::LockingJob::DEFAULT_LOCK_PROC

  discard_on ActiveJob::DeserializationError

  def perform(manual_dunning_period)
    with_write { manual_dunning_period.run }
  end
end
