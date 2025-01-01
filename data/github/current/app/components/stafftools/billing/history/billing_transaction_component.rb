# typed: true
# frozen_string_literal: true

module Stafftools::Billing::History
  class BillingTransactionComponent < ApplicationComponent
    extend T::Sig

    include Stafftools::BillingHelper
    include StaticAssetHelper

    attr_reader :payment

    sig { params(payment: Stafftools::Billing::PaymentRecord).void }
    def initialize(payment:)
      @payment = payment
    end

    private

    sig { returns(String) }
    def payment_status_label
      scheme = if payment.was_refunded?
        :attention
      elsif payment.success?
        :success
      else
        :danger
      end

      render Primer::Beta::Label.new(scheme: scheme, ml: 1, size: :large) do
        if payment.was_refunded?
          render Primer::Beta::Link.new(
            href: "javascript:void(0)",
            underline: false,
            color: :attention,
            title: "Refunded on #{payment.refund_at.strftime('%b %-d, %Y')}"
          ) do |_component|
            primer_octicon(icon: :clock, mr: 1) + payment.status_text
          end
        else
          payment.status_text
        end
      end
    end

    sig { returns(String) }
    def payment_method_information
      if payment.zero_charge?
        if payment.active_coupon
          safe_join(["Coupon for ", content_tag(:i, payment.active_coupon)])
        elsif payment.transaction_id.blank?
          "Pending Braintree charge"
        else
          "Zero charge transaction"
        end
      else
        if payment.credit_balance_adjustment_transaction?
          "Credit Balance Adjustment"
        elsif payment.paypal?
          render Primer::Alpha::Image.new(src: image_path("paypal/paypal-small.png"), alt: "PayPal", classes: "paypal-icon")
        else
          primer_octicon(:"credit-card", mr: 1)
        end + payment.payer_identifier
      end
    end

    sig { returns(String) }
    def transaction_status_klass
      if payment.was_refunded?
        "transaction-refunded"
      elsif payment.success?
        "transaction-success"
      else
        "transaction-failed"
      end
    end
  end
end
