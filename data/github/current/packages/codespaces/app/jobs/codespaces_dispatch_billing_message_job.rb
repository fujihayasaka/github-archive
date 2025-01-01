# typed: true
# frozen_string_literal: true

class CodespacesDispatchBillingMessageJob < CodespacesJob
  locked_by timeout: 1.minute, key: DEFAULT_LOCK_PROC
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
