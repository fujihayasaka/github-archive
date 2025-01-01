# typed: true
# frozen_string_literal: true

module Billing
  class StripeWebhook < ApplicationRecord::Ballast
    UnsupportedKind = Class.new(StandardError)
    RECENCY_THRESHOLD = 5.minutes

    store :payload, coder: JSON

    scope :ignoring_recent, -> { where("created_at < ?", RECENCY_THRESHOLD.ago) }

    scope :payouts, -> { where(kind: [:payout_created, :payout_failed]) }

    scope :most_recent_first, -> { order(id: :desc) }

    before_save :update_account_id_from_payload
    before_save :set_user_id
    after_commit :clear_latest_payout_cache, on: :create, if: :payout?

    belongs_to :user
    belongs_to :account, class_name: "Billing::StripeConnect::Account", primary_key: :stripe_account_id,
      foreign_key: :account_id, inverse_of: :webhooks

    # When adding a new webhook here, ensure that you also enable the event within Stripe
    # (https://dashboard.stripe.com/webhooks) so that it is sent to dotcom for tracking.  We currently have
    # two endpoints that are used for webhooks: `/billing/stripe/platform` and `/billing/stripe/connect`. Use
    # `/billing/stripe/platform` whenever GitHub is involved in the transaction (e.g., sponsorship) and use
    # `/billing/stripe/connect` when only the user's account changes or receives payouts.
    # See https://stripe.com/docs/api/events/types for the kinds of webhooks Stripe can send.
    #
    # Webhook kinds MUST map to the combination of the type listed in the payload and the event (with underscores),
    # e.g. for "payout.created", `payout` is the type and `created` is the event, resulting in "payout_created".
    #
    # If a corresponding payout ledger exists, kinds SHOULD correspond to transaction types for those
    # ledger entries to avoid confusion. See `Billing::PayoutsLedgerEntry` for transaction types.
    #
    # 10..11 - Unused (these ledger transactions do not come from Stripe webhooks)
    # 12..14 - Stripe Disputes (chargebacks)
    # 15..29 - Unused (these ledger transactions do not come from Stripe webhooks)
    # 30..39 - Stripe Transfers
    # 40..49 - Stripe Payouts
    # 50..59 - Stripe Fraud Warnings
    # 100..109 - Stripe Connect accounts
    # 110..119 - Stripe Invoices
    # 120..129 - Stripe Charges
    enum :kind, {
      unknown: 0,
      # Disputes
      charge_dispute_created: 12,
      charge_dispute_updated: 13,
      charge_dispute_closed: 14,
      # Transfers
      transfer_created: 30,
      transfer_reversed: 31,
      transfer_failed: 32,
      # Payouts
      payout_created: 40,
      payout_failed: 41,
      # Fraud
      radar_early_fraud_warning_created: 50,
      radar_early_fraud_warning_updated: 51,
      # Account
      account_updated: 100,
      # Invoices
      invoice_payment_succeeded: 110,
      # Charges
      charge_succeeded: 120,
      charge_failed: 121,
    }

    enum :status, {
      pending: "pending",
      processed: "processed",
      ignored: "ignored",
    }

    validates :status, presence: true, on: :create

    # Public: The class that is capable of handling the webhook payload.
    #
    # Returns Class responding to #perform
    # Raises UnsupportedKind exception if the webhook kind isn't supported
    def handler
      case kind.to_sym
      when :payout_created then GitHub::Billing::StripeWebhook::PayoutCreated
      when :payout_failed then GitHub::Billing::StripeWebhook::PayoutFailed
      when :transfer_created then GitHub::Billing::StripeWebhook::TransferCreated
      when :transfer_failed then GitHub::Billing::StripeWebhook::TransferFailed
      when :transfer_reversed then GitHub::Billing::StripeWebhook::TransferReversed
      when :account_updated then GitHub::Billing::StripeWebhook::AccountUpdated
      when :charge_dispute_created, :charge_dispute_updated, :charge_dispute_closed
        GitHub::Billing::StripeWebhook::ChargeDispute
      when :radar_early_fraud_warning_created, :radar_early_fraud_warning_updated
        GitHub::Billing::StripeWebhook::EarlyFraudWarning
      when :invoice_payment_succeeded then GitHub::Billing::StripeWebhook::PaymentSucceeded
      when :charge_succeeded then GitHub::Billing::StripeWebhook::ChargeSucceeded
      when :charge_failed then GitHub::Billing::StripeWebhook::ChargeFailed
      else
        raise UnsupportedKind, "Could not handle webhook kind: #{kind}"
      end
    end

    def payout?
      payout_created? || payout_failed?
    end

    # Public: Handle the webhook payload provided by Stripe
    #
    # Returns Boolean
    def perform
      return true if processed?

      handler.perform(self)
      update!(status: :processed, processed_at: Time.now)
    end

    sig { returns ::Stripe::Event }
    def stripe_event
      ::Stripe::Event.construct_from(payload)
    end

    # Public: Whether or not the webhook has been processed already
    #
    # Returns Boolean
    def processed?
      processed_at.present?
    end

    # Public: The URL for the Stripe Connect Account in the Stripe dashboard
    #
    # Returns String
    def connect_account_url
      "#{GitHub.stripe_connect_dashboard_base_url}/connect/accounts/#{account_id}"
    end

    def stripe_object_id
      payload.dig("data", "object", "id")
    end

    # Public: When the Stripe object represented by this record was created.
    #
    # Returns a DateTime or nil.
    def stripe_object_created
      # e.g., https://stripe.com/docs/api/payouts/object#payout_object-created
      created_timestamp = payload.dig("data", "object", "created")
      return unless created_timestamp

      Time.at(created_timestamp).to_datetime
    end

    # Private: Not all webhooks have the account ID in the payload, e.g., charge_succeeded, but some do.
    def update_account_id_from_payload
      new_value = case kind.to_sym
      when :payout_created, :payout_failed, :account_updated, :early_fraud_warning
        payload["account"]
      when :transfer_created, :transfer_failed, :transfer_reversed
        payload["data"]["object"]["destination"]
      end
      if new_value.present?
        self.account_id = new_value
      end
    end

    def set_user_id
      return if user_id.present?

      if account
        self.user_id = T.must(account).sponsorable_id
      elsif charge_failed? || charge_succeeded?
        charge = T.cast(stripe_event.data.object, ::Stripe::Charge)
        user_id_str = charge.billing_details["name"]
        return if user_id_str.blank?

        potential_user_id = user_id_str.to_i
        return if potential_user_id < 1 # non-numeric strings will be converted to 0, which isn't a valid User ID

        self.user_id = potential_user_id
      end
    end

    def clear_latest_payout_cache
      cache_key = Billing::StripeConnect::Account.latest_payout_status_cache_key_for(T.must(account_id))
      Billing::Kv.store.del(cache_key)
    end
  end
end
