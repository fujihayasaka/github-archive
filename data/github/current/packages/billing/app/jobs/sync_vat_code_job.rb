# typed: strict
# frozen_string_literal: true

class SyncVatCodeJob < BillingJob
  include GitHub::Billing::ZuoraRateLimitHandler

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

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

  sig { params(zuora_account_id: String, vat_code: T.nilable(String)).void }
  def perform(zuora_account_id:, vat_code:)
    response = GitHub.zuorest_client.update_account(zuora_account_id, { taxInfo: { VATId: vat_code } }, { "Content-Type" => "application/json" })
    result = GitHub::Billing::Result.from_zuora(response)
    unless result.success?
      GitHub.logger.error(
        "Failed to sync vat code with Zuora",
        "code.namespace" => self.class.name,
        "gh.billing.zuora.account.id" => zuora_account_id,
        "gh.billing.zuora.vat_code" => vat_code,
        "gh.billing.zuora.response.success" => result.success?,
        "gh.billing.zuora.response.error_message" => result.error_message,
        "gh.billing.zuora.response.request_id" => response["requestId"],
      )
      GitHub.dogstats.increment("billing.sync_vat_code.failure")
    end
  end
end
