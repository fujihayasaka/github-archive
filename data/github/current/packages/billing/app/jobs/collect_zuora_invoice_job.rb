# typed: strict
# frozen_string_literal: true

class CollectZuoraInvoiceJob < ApplicationJob
  include GitHub::Billing::ZuoraRateLimitHandler

  queue_as :zuora

  rescue_from(Zuorest::TooManyRequestsError) do |error|
    T.bind(self, CollectZuoraInvoiceJob)

    zuora_rate_limit_handler(self, error)
  end

  # Attempts to collect the invoice for the given ID.
  # Because invoices are collected daily by Zuora, a failure to collect
  # in this job is not critical since it will be done by Zuora for us.
  #
  # zuora_account_id - The String representing the user's Zuora account ID
  # invoice_id - The String long format identifying the invoice in Zuora
  sig { params(zuora_account_id: String, invoice_id: String).void }
  def perform(zuora_account_id, invoice_id)
    GitHub.zuorest_client.timeout = 120
    GitHub.zuorest_client.open_timeout = 120

    GitHub.zuorest_client.create_invoice_collect({
      accountKey: zuora_account_id,
      invoiceId: invoice_id,
    })
  rescue Zuorest::HttpError, Faraday::Error => e
    Failbot.report!(e, app: "github-zuora")
    # If this API call fails for any reason, exception or error in Zuora/Gateway
    # the invoice will be collected on the next Payment Run and dun if necessary
  end
end
