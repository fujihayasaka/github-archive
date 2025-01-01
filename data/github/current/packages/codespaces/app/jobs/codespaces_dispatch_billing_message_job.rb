# typed: true
# frozen_string_literal: true

class CodespacesDispatchBillingMessageJob < CodespacesJob
  # Locked_by timeout bumped from 1 min to 5 mins to address edge case where a tiny fraction of Codespace usage
  # has the possibility of being processed twice. See more here:
  # https://github.com/github/codespaces/issues/20648#issuecomment-2830826036
  locked_by timeout: 5.minutes, key: DEFAULT_LOCK_PROC
  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  # TODO: Make `message` required and drop `message_body` after fully deployed
  def perform(message: nil, message_body:, vscs_target:, codespace_plan_id:)
    Codespaces::Billing::DispatchMessage.call(
      message:,
      message_body: message_body,
      vscs_target: vscs_target,
      codespace_plan_id: codespace_plan_id,
    )
  end
end
