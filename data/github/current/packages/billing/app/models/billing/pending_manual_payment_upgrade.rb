# typed: strict
# frozen_string_literal: true

module Billing
  # Describes how to finalize a deferred upgrade after a manual (e.g. India RBI) payment succeeds on
  # the Zuora Hosted Payment Page: the path to POST to and the params to send.
  #
  # A product that collects an advance payment on upgrade builds one of these and passes it to
  # Billing::ManualPaymentRedirect#redirect_to_manual_payment_if_required. The manual payments page
  # then renders a hidden form (submitted by billing/zuora.ts once the payment is confirmed) that
  # re-issues the original upgrade request to the product's create endpoint. This keeps billing free
  # of product-specific knowledge — the product owns the path and params, while the redirect flow is
  # handled in one place by Billing::ManualPaymentRedirect.
  #
  # The pending upgrade is stashed in Billing::Kv (scoped to the customer + advance invoice) so it
  # survives the redirect to the manual payments page and a page refresh, then expires on its own.
  #
  # `params` may contain nested Hashes, which are rendered as `name[nested]` form fields.
  class PendingManualPaymentUpgrade < T::Struct
    const :path, String
    const :params, T::Hash[String, T.untyped]

    # How long a pending upgrade is retained while the customer completes the manual payment.
    # The advance invoice it finalizes is itself short-lived, so a day comfortably covers a payment
    # session without leaving stale entries around.
    TTL = T.let(1.day, ActiveSupport::Duration)

    # Explicit serialization (rather than the built-in T::Struct#serialize, which can behave
    # surprisingly with nested props) kept symmetric with #deserialize_json.
    sig { returns(T::Hash[String, T.untyped]) }
    def to_hash
      { "path" => path, "params" => params }
    end

    # Stash the pending upgrade for `target`'s upcoming manual payment of `invoice_id`. No-op when the
    # target has no billing customer (in which case no advance payment could have been collected).
    sig { params(target: ::Billing::Types::Account, invoice_id: String, pending_upgrade: PendingManualPaymentUpgrade).void }
    def self.store(target:, invoice_id:, pending_upgrade:)
      key = key_for(target, invoice_id)
      return if key.nil?

      ::Billing::Kv.store.set(key, pending_upgrade.to_hash.to_json, expires: TTL.from_now)
    end

    # The pending upgrade previously stashed for `target` + `invoice_id`, or nil when none is pending.
    sig { params(target: ::Billing::Types::Account, invoice_id: T.nilable(String)).returns(T.nilable(PendingManualPaymentUpgrade)) }
    def self.fetch(target:, invoice_id:)
      return nil if invoice_id.blank?

      key = key_for(target, invoice_id)
      return nil if key.nil?

      raw = ::Billing::Kv.store.get(key).value! { nil }
      return nil if raw.nil?

      deserialize_json(raw)
    end

    # Removes any pending upgrade stashed for `target` + `invoice_id`. Used when the customer abandons
    # the deferred upgrade. No-op when nothing is stashed (or the target has no billing customer).
    sig { params(target: ::Billing::Types::Account, invoice_id: T.nilable(String)).void }
    def self.delete(target:, invoice_id:)
      return if invoice_id.blank?

      key = key_for(target, invoice_id)
      return if key.nil?

      ::Billing::Kv.store.del(key)
    end

    sig { params(target: ::Billing::Types::Account, invoice_id: String).returns(T.nilable(String)) }
    private_class_method def self.key_for(target, invoice_id)
      customer_id = target.customer&.id
      return nil if customer_id.nil?

      "billing.customer.#{customer_id}.pending_manual_payment_upgrade.#{invoice_id}"
    end

    sig { params(raw: String).returns(T.nilable(PendingManualPaymentUpgrade)) }
    private_class_method def self.deserialize_json(raw)
      data = JSON.parse(raw)
      new(path: data.fetch("path"), params: data.fetch("params"))
    rescue JSON::ParserError, KeyError
      nil
    end
  end
end
