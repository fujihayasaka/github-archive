# typed: strict
# frozen_string_literal: true

class SyncZuoraTaxExemptStatusJob < BillingJob
  include GitHub::Billing::ZuoraRateLimitHandler

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  queue_as :billing

  retry_on GitHub::Restraint::UnableToLock,
    attempts: 3,
    wait: :polynomially_longer

  ::Billing::Zuora::RETRYABLE_ERRORS.each do |error|
    retry_on(error, wait: :polynomially_longer) do |_job, error|
      Failbot.report(error)
    end
  end

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
    if tax_exemption_status.blank?
      GitHub.logger.error(
        "Tax exemption status not found",
        logger_fields(zuora_account_id).merge({ "gh.billing.tax_exemption_status.id": tax_exemption_status_id })
      )
      return
    end

    zuora_tax_exempt_status = ZuoraTaxExemptStatuses::Yes.serialize
    if tax_exemption_status.rejected?
      zuora_tax_exempt_status = ZuoraTaxExemptStatuses::No.serialize
    end

    response = GitHub.zuorest_client.update_account(zuora_account_id, {
      taxInfo: {
        exemptStatus: zuora_tax_exempt_status,
        exemptCertificateId: tax_exemption_status_id.to_s
      }
    }, { "Content-Type" => "application/json" })

    if response["success"]
      GitHub.logger.info("Updated tax exempt status in Zuora", logger_fields(zuora_account_id, tax_exemption_status:, response:))
    else
      GitHub.logger.error("Failed to update tax exempt status in Zuora", logger_fields(zuora_account_id, tax_exemption_status:, response:))
    end
  end

  sig { params(zuora_account_id: String, tax_exemption_status: T.nilable(Billing::TaxExemptionStatus), response: T.untyped).returns(T::Hash[Symbol, T.untyped]) }
  def logger_fields(zuora_account_id, tax_exemption_status: nil, response: nil)
    log_context = {
      "code.namespace": self.class.name,
      "gh.billing.customer.id": tax_exemption_status&.customer_id,
      "gh.billing.tax_exemption_status.id": tax_exemption_status&.id,
      "gh.billing.tax_exemption_status.status": tax_exemption_status&.status,
      "gh.billing.zuora.account.id": zuora_account_id,
      "gh.billing.zuora.response": response,
    }
  end
end
