# typed: strict
# frozen_string_literal: true

class CreditCheckStatusPollJob < CreditDecisionEngine::AbstractCreditCheckStatusPollJob
  extend T::Sig
  extend T::Helpers

  class CreditCheckMissing < StandardError; end

  queue_as :credit_check

  schedule interval: 2.minutes, condition: -> { GitHub.billing_enabled? }

  MAX_CREDIT_CHECKS_TO_PROCESS = 10

  sig { void }
  def perform
    process_credit_checks(credit_checks_to_process: MAX_CREDIT_CHECKS_TO_PROCESS)
  end

  private

  sig { override.params(request_id: String, status: Symbol).void }
  def process_credit_check(request_id:, status:)
    credit_check = with_write { Billing::CreditCheck.find_by(request_id: request_id) }
    if credit_check.nil?
      Failbot.report(CreditCheckMissing.new("CreditCheck not found for request_id: #{request_id} with received status: #{status}"))
      return
    end

    with_write { credit_check.update!(status: status) }
  end
end
