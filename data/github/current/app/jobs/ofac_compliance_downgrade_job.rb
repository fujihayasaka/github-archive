# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class OFACComplianceDowngradeJob < ApplicationJob
  queue_as :trade_controls
  retry_on_dirty_exit

  discard_on ActiveJob::DeserializationError

  def perform(downgrade)
    if downgrade.incomplete?
      log_past_scheduled_date_to_dogstats(downgrade.user) if downgrade.past_scheduled_run_date?
      with_write do
        downgrade.run
      end
    end
  rescue ::Faraday::TimeoutError => e
    log_exception_to_dogstats(downgrade.user)
  end

  def is_retry?
    executions > 1
  end

  def log_exception_to_dogstats(user)
    return if is_retry?

    GitHub.dogstats.increment(
        "billing.trade_controls_restriction.downgrade.downgrade_not_successful",
        tags: ["user:#{user}", "actor:#{user}", "reason: Timeout error when cancelling subscription"],
    )
  end

  def log_past_scheduled_date_to_dogstats(user)
    return if is_retry?

    GitHub.dogstats.increment(
        "billing.trade_controls_restriction.downgrade.downgrade_past_scheduled_run_date",
        tags: ["user:#{user}", "actor:#{user}"],
    )
  end
end
