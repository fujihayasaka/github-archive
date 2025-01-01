# typed: true
# frozen_string_literal: true

module Codespaces
  class VscodeBillingThresholdNotifierJob < CodespacesJob
    locked_by timeout: 5.minutes, key: DEFAULT_LOCK_PROC
    retry_on_dirty_exit
    retry_on_recoverable_exceptions

    def perform(billable_owner:, codespace:)
      Codespaces::Billing::VscodeThresholdNotifier.call(
        billable_owner: billable_owner,
        codespace: codespace
      )
    end
  end
end
