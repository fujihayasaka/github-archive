# typed: strict
# frozen_string_literal: true

class SyncZuoraTaxExemptStatusJob < BillingJob
  extend T::Sig
  include GitHub::Billing::ZuoraRateLimitHandler

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  queue_as :billing

  retry_on GitHub::Restraint::UnableToLock,
    attempts: 3,
    wait: :polynomially_longer

  T.unsafe(self).retry_on(*Billing::Zuora::RETRYABLE_ERRORS)

  rescue_from(Zuorest::TooManyRequestsError) do |error|
    T.bind(self, SyncZuoraTaxExemptStatusJob)

    zuora_rate_limit_handler(self, error)
  end

  class ZuoraTaxExemptStatuses < T::Enum
    enums do
      Yes = new("Yes")
      No = new("No")
      PendingVerification = new("PendingVerification")
    end
  end

  sig { params(zuora_account_id: String, tax_exemption_status_id: Integer).void }
  def perform(zuora_account_id:, tax_exemption_status_id:)
    tax_exemption_status = Billing::TaxExemptionStatus.find_by(id: tax_exemption_status_id)
    return unless tax_exemption_status

    zuora_tax_exempt_status = ZuoraTaxExemptStatuses::Yes.serialize
    if tax_exemption_status.rejected?
      zuora_tax_exempt_status = ZuoraTaxExemptStatuses::No.serialize
    end

    GitHub.zuorest_client.update_account(zuora_account_id, { taxInfo: { exemptStatus: zuora_tax_exempt_status } }, { "Content-Type" => "application/json" })
  end
end
