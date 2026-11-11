# typed: strict
# frozen_string_literal: true

module Copilot
  # Banner prompting an India RBI customer to complete an outstanding manual payment for a Copilot
  # plan upgrade (Pro/Pro+/Max). RBI customers must authorize card payments manually; if they started
  # an upgrade but didn't finish paying, the advance-payment invoice sits uncollected and the upgrade
  # never finalizes. This links them to the manual payments page to pay it and activate their plan.
  #
  # Renders nothing unless the customer has automatic payments disabled by RBI, the feature is enabled,
  # and an outstanding Copilot upgrade invoice exists (see Billing::ManualPayment).
  class OutstandingUpgradePaymentBannerComponent < ApplicationComponent
    include GitHub::Memoizer

    # A pending advance-payment invoice paired with the individual Copilot upgrade product it pays for.
    class OutstandingUpgrade < T::Struct
      const :invoice_id, String
      const :product, ::Billing::ProductUUID
    end

    sig { params(user: ::User).void }
    def initialize(user:)
      @user = user
    end

    private

    sig { returns(T::Boolean) }
    def render?
      return false unless GitHub.billing_enabled?
      # Suppressed on the manual payments page (bill_pay) the banner links to, to avoid a circular prompt.
      return false if controller.controller_path == "billing_settings/payments"
      return false unless @user.autopay_disabled_by_india_rbi?
      return false unless FeatureFlag.vexi.enabled?(:copilot_rbi_manual_payment_signup, @user, default: false)

      outstanding_upgrade.present?
    end

    # The first pending advance payment (invoice + product) that is for an individual Copilot plan
    # upgrade (Pro/Pro+/Max), or nil when there is none. Other Copilot SKUs (Business/Enterprise) and
    # pay-as-you-go usage are excluded.
    sig { returns(T.nilable(OutstandingUpgrade)) }
    memoize def outstanding_upgrade
      customer = @user.customer
      return nil if customer.nil?

      ::Billing::AdvancePayment.pending_invoice_ids(customer: customer).each do |invoice_id|
        product = ::Billing::ManualPayment.new(target: @user, invoice_id: invoice_id).invoice_product
        next if product.nil?
        next unless product.product_type == ::Billing::ProductUUID::COPILOT_PRODUCT_TYPE
        next unless ::Copilot::INDIVIDUAL_PRODUCT_KEYS.include?(product.product_key)

        return OutstandingUpgrade.new(invoice_id: invoice_id, product: product)
      end

      nil
    end

    sig { returns(T.nilable(String)) }
    def outstanding_invoice_id
      outstanding_upgrade&.invoice_id
    end

    sig { returns(T.nilable(String)) }
    def product_name
      outstanding_upgrade&.product&.name
    end

    sig { returns(String) }
    def pay_path
      bill_pay_new_path(invoice_id: outstanding_invoice_id)
    end

    sig { returns(String) }
    def cancel_path
      bill_pay_cancel_pending_path(invoice_id: outstanding_invoice_id)
    end
  end
end
