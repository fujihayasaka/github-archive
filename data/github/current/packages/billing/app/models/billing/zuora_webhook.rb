# typed: true
# frozen_string_literal: true

module Billing
  # Zuora sends GitHub webhooks with events that we process in order to sync data within our system.
  # ref: https://github.com/github/gitcoin/blob/main/docs/technical/Metered%20Billing/invoiced-customers.md#zuora-webhooks
  class ZuoraWebhook < ApplicationRecord::Ballast
    include GitHub::VexiActor
    include GitHub::Memoizer

    class RetryableError < StandardError; end
    class UnableToLock < StandardError; end
    class Deferred < StandardError; end

    RETRYABLE_ERRORS = T.let(::Billing::Zuora::RETRYABLE_ERRORS + [
      ::Billing::Zuora::LockCompetitionError,
      ::Billing::ZuoraWebhook::RetryableError,
      ::Braintree::UnexpectedError,
      ::Stripe::APIConnectionError,
      ::Stripe::APIError,
      ActiveRecord::AdapterTimeout,
      ActiveRecord::ConnectionNotEstablished,
      ActiveRecord::QueryCanceled,
      Audit::EventForwarder::SubscribeError,
      WaitForReplication::DataUnavailable
    ].freeze, T::Array[T.class_of(StandardError)])

    RECENCY_THRESHOLD = T.let(5.minutes, ActiveSupport::Duration)
    STALE_THRESHOLD = T.let(3.hours, ActiveSupport::Duration)

    SALES_SERVE_KINDS = T.let(
      %w[
        amendment_processed
        subscription_created
        subscription_deleted
      ].freeze,
      T::Array[String]
    )

    store :payload, coder: JSON

    attr_readonly :kind, :account_id, :payload

    enum :kind, {
      payment_processed: 0,
      payment_declined: 1,
      payment_refund_processed: 2,
      invoice_posted: 3,
      amendment_processed: 4,
      subscription_created: 5,
      account_updated: 6,
      credit_balance_used_for_invoice: 7,
      subscription_deleted: 8,
      webhook_test: 1000
    }

    enum :status, {
      pending: "pending",
      processed: "processed",
      ignored: "ignored",
      investigating: "investigating"
    }
    scope :not_processed, -> { where.not(status: :processed) }
    scope :not_ignored, -> { where.not(status: :ignored) }

    validates :status, presence: true, on: :create
    validates :investigation_notes, presence: true, on: :update, if: -> (webhook) { webhook.status == "investigating" }

    scope :invoiced,        -> { where(kind: SALES_SERVE_KINDS) }
    scope :not_sales_serve, -> { where.not(kind: SALES_SERVE_KINDS) }
    scope :ignoring_recent, -> { where("created_at < ?", RECENCY_THRESHOLD.ago) }
    scope :stale, -> { where("created_at < ?", STALE_THRESHOLD.ago) }

    sig { params(payload: T::Hash[String, T.untyped]).void }
    def self.receive(payload)
      category = payload.delete("event_category")&.underscore&.parameterize(separator: "_")
      GitHub.dogstats.increment("zuora.webhook", tags: ["category:#{category}"])

      return if category.nil?

      webhook = create!(
        kind: category,
        status: :pending,
        account_id: payload["AccountId"],
        payload: payload,
      )

      if SALES_SERVE_KINDS.include?(category)
        ZuoraWebhookJob.perform_later(webhook)
      elsif FeatureFlag.vexi.enabled?(:zuora_webhook_stream_processor, default: false)
        result = Hydro::PublishRetrier.publish(
          { webhook_id: webhook.id },
          publisher: GitHub.sync_hydro_publisher,
          schema: "github.billing.v0.ZuoraWebhook",
          partition_key: webhook.account_id,
        )

        GitHub.logger.info("Published Zuora webhook to Hydro", {
          "code.namespace" => "Billing::ZuoraWebhook",
          "code.function" => "receive",
          "gh.billing.zuora.webhook.id" => webhook.id,
          "gh.hydro.result" => result.inspect,
          "gh.hydro.partition_key" => webhook.account_id,
        })
      else
        ZuoraWebhookJob.perform_later(webhook)
      end
    rescue StandardError => e
      GitHub.dogstats.increment("zuora.webhook.exception", tags: ["category:#{category}", "error:#{e.class.name}"])
      raise e
    end

    sig { returns(T::Boolean) }
    def ignore!
      update!(status: :ignored, processed_at: Time.now)
    end

    # Reschedule this webhook to be processed again after the provided delay.
    sig { params(wait: T.any(ActiveSupport::Duration, Numeric), reason: String).void }
    def reschedule!(wait:, reason:)
      ZuoraWebhookJob.set(wait: wait).perform_later(self)
      GitHub.dogstats.increment("zuora.webhook.rescheduled", tags: ["category:#{kind}", "reason:#{reason}"])
      raise Deferred
    end

    # Public: Has this webhook been processed?
    #
    # Returns Boolean
    sig { returns(T::Boolean) }
    def processed?
      processed_at.present?
    end

    sig { returns(T::Boolean) }
    def is_sales_serve_kind?
      SALES_SERVE_KINDS.include?(kind.to_s)
    end

    sig { returns(T::Boolean) }
    def business_account?
      account.is_a?(Business)
    end

    sig { returns(T::Boolean) }
    def user_account?
      account.is_a?(User)
    end

    # Check if there is an active account associated with the webhook.
    sig { returns(T::Boolean) }
    def account_deleted?
      return true if account.nil?
      # Soft deleted accounts can be restored so we should not treat them as deleted
      return false if account.respond_to?(:soft_deleted?) && T.unsafe(account).soft_deleted?

      user_account? && T.cast(account, ::User).deleted?
    end

    sig { returns(T::Boolean) }
    def account_suspended?
      account&.suspended? || false
    end

    sig { returns(T::Boolean) }
    def account_sdn_suspended?
      account&.sdn_suspended? || false
    end

    # Public: The invoice ID in the webhook payload
    #
    # Returns String
    sig { returns(T.nilable(String)) }
    def invoice_id
      payload["InvoiceId"]
    end

    # Public: The payment ID in the webhook payload
    #
    # Depending on the type of webhook, this may be PaymentId or PaymentID in the
    # webhook payload
    #
    # Returns String
    sig { returns(T.nilable(String)) }
    def payment_id
      payload["PaymentId"]
    end

    # Public: The refund ID in the webhook payload
    #
    # Returns String
    sig { returns(T.nilable(String)) }
    def refund_id
      payload["RefundId"]
    end

    # Public: The subscription ID in the webhook payload
    #
    # Returns String
    sig { returns(T.nilable(String)) }
    def subscription_id
      payload["subscription_id"]
    end

    # Public: The class which handles this type of webhook
    #
    # Returns Class
    # sig { returns(T.class_of(::Billing::Zuora::Webhooks::WebhookHandler)) }
    def handler
      case kind.to_sym
      when :payment_processed then Billing::Zuora::Webhooks::PaymentProcessed
      when :payment_declined then Billing::Zuora::Webhooks::PaymentDeclined
      when :payment_refund_processed then Billing::Zuora::Webhooks::PaymentRefundProcessed
      when :invoice_posted then Billing::Zuora::Webhooks::InvoicePosted
      when :amendment_processed then Billing::Zuora::Webhooks::AmendmentProcessed
      when :subscription_created then Billing::Zuora::Webhooks::SubscriptionCreated
      when :subscription_deleted then Billing::Zuora::Webhooks::SubscriptionDeleted
      when :account_updated then Billing::Zuora::Webhooks::AccountUpdated
      when :credit_balance_used_for_invoice then Billing::Zuora::Webhooks::CreditBalanceUsedForInvoice
      when :webhook_test then Billing::Zuora::Webhooks::TestHandler
      end
    end

    # Public: Perform this webhook and mark it as processed
    #
    # Returns Boolean
    sig { params(restraint: GitHub::Restraint).returns(T::Boolean) }
    def perform(restraint: GitHub::Restraint.new)
      restraint.lock!(lock_key, _n = 1, _ttl = 5.minutes) do
        if processed?
          GitHub.dogstats.increment("zuora.webhook.already_processed", tags: ["category:#{kind}"])
          return true
        elsif pending?
          latency_ms = (Time.now.to_f - created_at.to_f) * 1_000
          GitHub.dogstats.timing("zuora.webhook_latency", latency_ms.to_i)
        end

        result = handler.perform(self)
        if result != false
          update!(status: :processed, processed_at: Time.now)
        else
          ignore!
        end

        result != false
      end
    rescue Billing::ZuoraWebhook::Deferred
      # A handler rescheduled this webhook for later processing (e.g. an invoice awaiting reconciliation).
      # It has already enqueued a delayed retry, so leave the webhook pending and unprocessed.
      false
    rescue GitHub::Restraint::UnableToLock => e
      # We encounter this error occasionally and it's not clear whether there is actually another instance of the
      # webhook being processed or if the lock acquiring failed due to other reasons.
      # To help determine this, we retry immediately to rule out intermittent issues and then retry up to the TTL
      # to determine if the lock was previously not released correctly.
      retries ||= 0
      if (retries += 1) < 7
        sleep 60 if retries > 1
        GitHub.dogstats.increment("zuora.webhook.retry", tags: ["error:#{e.class.name}", "retries:#{retries}"])
        retry
      end
      raise Billing::ZuoraWebhook::UnableToLock
    ensure
      if FeatureFlag.vexi.enabled?(:billing_handle_unprocessed_webhooks, default: false) && !processed?
        cache_performed_at
      end
    end

    # Public: The URL linking this webhook to the customer in Zuora
    #
    # Returns string
    sig { returns(String) }
    def customer_account_url
      "#{GitHub.zuora_host}/apps/CustomerAccount.do?method=view&id=#{account_id}"
    end

    sig { returns(T.nilable(String)) }
    def investigation_notes_url
      return unless investigation_notes.present?
      URI.extract(investigation_notes, %w(http https)).first
    end

    sig { returns(T.nilable(String)) }
    def investigation_notes_url_name
      return unless investigation_url = investigation_notes_url
      uri = URI.parse(investigation_url) rescue nil
      return unless uri && uri.host
      domain = PublicSuffix.parse(uri.host) rescue nil
      return unless domain

      if domain.sld == "github"
        # This gets the issue id from the GitHub issue URL
        if uri.path =~ %r{^/([^/]+/[^/]+)/issues/(\d+)}
          return "#{$1}##{$2}"
        end
      end
      "#{domain.sld.capitalize} Link" if domain
    end

    sig { returns(T.nilable(Billing::Types::Account)) }
    memoize def account
      plan_subscription&.billable_entity
    end

    sig { returns(T.nilable(Customer)) }
    memoize def customer
      plan_subscription&.customer
    end

    sig { returns(T.nilable(Billing::PlanSubscription)) }
    memoize def plan_subscription
      PlanSubscription.joins(:customer).find_by(customers: { zuora_account_id: account_id })
    end

    sig { returns(T.nilable(Time)) }
    def performed_at
      value = Billing::Kv.store.get(performed_at_key).value { nil }
      value ? Time.iso8601(value) : nil
    end

    private

    sig { returns(String) }
    def lock_key
      "ZuoraWebhookJob-#{id}"
    end

    sig { void }
    def cache_performed_at
      Billing::Kv::DataStore.with_write do
        Billing::Kv.store.set(performed_at_key, Time.now.iso8601, expires: 1.month.from_now)
      end
    end

    sig { returns(String) }
    def performed_at_key
      "ZuoraWebhook-#{id}-performed_at"
    end
  end
end
