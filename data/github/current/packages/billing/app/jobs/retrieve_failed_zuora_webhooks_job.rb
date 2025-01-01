# typed: true
# frozen_string_literal: true

class RetrieveFailedZuoraWebhooksJob < ApplicationJob
  schedule interval: 12.hours, condition: -> { GitHub.billing_enabled? }

  queue_as :zuora
  retry_on_dirty_exit

  WEBHOOK_URL = "/v1/notification-history/callout"
  PAGE_SIZE = 40
  ZUORA_TIMESTAMP_FORMAT = "%Y-%m-%dT%H:%M:%S"

  PAYMENT_PROCESSED        = :payment_processed
  PAYMENT_DECLINED         = :payment_declined
  PAYMENT_REFUND_PROCESSED = :payment_refund_processed
  INVOICE_POSTED           = :invoice_posted
  AMENDMENT_PROCESSED      = :amendment_processed
  SUBSCRIPTION_CREATED     = :subscription_created
  CREDIT_BALANCE_USED_FOR_INVOICE = :credit_balance_used_for_invoice

  EVENT_CATEGORIES = [
    "2120",
    "2110",
    "2410",
    "1110",
    "1310",
    "1210",
    "user.notification:CreditBalanceUsedForInvoice",
  ].freeze

  EVENT_KINDS = {
    "2120" => PAYMENT_PROCESSED,
    "2110" => PAYMENT_DECLINED,
    "2410" => PAYMENT_REFUND_PROCESSED,
    "1110" => INVOICE_POSTED,
    "1310" => AMENDMENT_PROCESSED,
    "1210" => SUBSCRIPTION_CREATED,
    "Credit Balance Used For Invoice (custom event)" => CREDIT_BALANCE_USED_FOR_INVOICE,
  }.freeze

  PAYMENT_ID = "<Payment.ID>"
  REFUND_ID  = "<Refund.ID>"
  ACCOUNT_ID = "<Account.ID>"
  ALT_ACCOUNT_ID = "<Account.Id>"
  INVOICE_ID = "<Invoice.ID>"
  SUBSCRIPTION_STAMP = "<Subscription.Stamp__c>"
  ACCOUNT_STAMP = "<Account.Stamp__c>"

  REPROCESSABLE_CODES = %w[401 405 408 429 -2000].freeze

  # Public: create webhook records from the failed but retryable zuora callouts
  #
  # Failbot.report-ing of the commonly experienced exceptions. Instead of failing on these we
  # continue to the next record to process.
  #
  # start_at - fetch records starting at this timestamp (default, provided on Zuora's side, is 1.day.ago)
  # end_at - fetch records up to this timestamp (default, provided on Zuora's side, is Time.current)
  #
  # Returns nothing.
  def perform(start_at: nil, end_at: nil)
    EVENT_CATEGORIES.each do |code|
      params = { "pageSize" => PAGE_SIZE, "eventCategory" => code }
      params["startTime"] = format_time_api_param(start_at) if start_at.present?
      params["endTime"] = format_time_api_param(end_at) if end_at.present?

      url = URI::HTTP.build(path: WEBHOOK_URL, query: params.to_query).request_uri

      while url.present?
        response = GitHub.zuorest_client.get(url) # rubocop:disable GitHub/ZuoraRestVerbs

        webhooks = filter_webhooks(response["calloutHistories"])

        records = upsert_records(webhooks)
        enqueue_processing_jobs(records)

        url = response["nextPage"]
      end
    end
  end

  private

  # Private: filter the webhooks for the current stamp only
  #
  # Returns an array of hashes (each one represents a failed Zuora webhook)
  sig { params(webhooks: T::Array[T::Hash[String, T.untyped]]).returns(T::Array[T::Hash[String, T.untyped]]) }
  def webhooks_for_current_stamp(webhooks)
    current_stamp = GitHub::Config::Proxima.current_stamp_or_dotcom
    webhooks.select do |w|
      webhook_stamp = w["eventContext"][ACCOUNT_STAMP] || w["eventContext"][SUBSCRIPTION_STAMP]
      webhook_stamp == current_stamp || (webhook_stamp.blank? && current_stamp == "dotcom")
    end
  end

  # Private: if the flag is enabled, filters for webhooks for the current stamp only. Always filters for retryable webhooks.
  #
  # Returns an array of hashes (each one represents a failed Zuora webhook)
  sig { params(webhooks: T::Array[T::Hash[String, T.untyped]]).returns(T::Array[T::Hash[String, T.untyped]]) }
  def filter_webhooks(webhooks)
    webhooks = webhooks_for_current_stamp(webhooks)
    retryable_webhooks(webhooks)
  end

  # Private: filter the webhooks down to just the retryable ones
  #
  # Returns an array of hashes (each representing a zuora calloutHistory)
  def retryable_webhooks(webhooks)
    webhooks.select { |w| REPROCESSABLE_CODES.include?(w["responseCode"].to_s) }
  end

  # Private: upsert database records for each webhook
  #
  # Returns an array of ::Billing::ZuoraWebhook records
  def upsert_records(webhooks)
    webhooks.filter_map do |webhook|
      event_context = webhook["eventContext"]
      account_id    = event_context[ACCOUNT_ID] || event_context[ALT_ACCOUNT_ID]
      kind          = EVENT_KINDS[webhook["eventCategory"]]

      with_write do
        webhook_record = upsert_record(kind: kind, account_id: account_id, payload: build_payload(kind, event_context))

        if webhook_record.pending?
          log_failed_webhook(kind, additional_tags: ["response_code:#{webhook["responseCode"]}"])
          webhook_record
        end
      end
    end
  end

  # Private: enqueue jobs to process the webhooks
  #
  # Returns nothing
  def enqueue_processing_jobs(records)
    records.each do |record|
      ZuoraWebhookJob.perform_later(record)
    end
  end

  # Private: log a failed webhook webhook to dogstats
  #
  # Returns nothing.
  def log_failed_webhook(kind, additional_tags: [])
    GitHub.dogstats.increment("zuora.webhook", tags: ["failure:true", "category:#{kind}"] + additional_tags)
  end

  # Private: Creates a webhook record if one does not exist with passed attrs
  #
  # Returns an instance of ::Billing::ZuoraWebhook
  def upsert_record(attributes)
    ::Billing::ZuoraWebhook.find_by(attributes) ||
      ::Billing::ZuoraWebhook.create!(attributes.merge(status: :pending))
  end

  # Private: builds the payload hash for the webhook record
  #
  # Returns a hash
  def build_payload(kind, event_context)
    case kind
    when PAYMENT_PROCESSED, PAYMENT_DECLINED
      build_payment_payload(event_context)
    when PAYMENT_REFUND_PROCESSED
      build_refund_payload(event_context)
    when INVOICE_POSTED
      build_invoice_payload(event_context)
    when AMENDMENT_PROCESSED, SUBSCRIPTION_CREATED
      build_subscription_payload(event_context)
    when CREDIT_BALANCE_USED_FOR_INVOICE
      build_credit_balance_used_for_invoice_payload(event_context)
    end
  end

  def build_refund_payload(event_context)
    {
      "RefundId"  => event_context[REFUND_ID],
      "PaymentId" => event_context[PAYMENT_ID],
    }
  end

  def build_payment_payload(event_context)
    {
      "AccountId" => event_context[ACCOUNT_ID],
      "PaymentId" => event_context[PAYMENT_ID],
    }
  end

  def build_invoice_payload(event_context)
    {
      "AccountId" => event_context[ACCOUNT_ID],
      "InvoiceId" => event_context[INVOICE_ID],
    }
  end

  def build_subscription_payload(event_context)
    {
      "subscription_id" => event_context["<Subscription.ID>"],
    }
  end

  def build_credit_balance_used_for_invoice_payload(event_context)
    JSON.parse(event_context["<sendXML>"])
  end

  # Private: changes the time's time zone to the billing time zone and then formats it in Zuora's format
  #
  # Returns a string representation of the time in the correct time zone and format
  def format_time_api_param(time)
    time.in_time_zone(GitHub::Billing.timezone).strftime(ZUORA_TIMESTAMP_FORMAT)
  end
end
