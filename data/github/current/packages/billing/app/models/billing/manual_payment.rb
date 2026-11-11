# typed: strict
# frozen_string_literal: true

# PORO that supports translating our domain idea of separating funds via manual payments
# with Zuora's data on invoices that are currently due.
module Billing
  class ManualPayment
    include GitHub::Memoizer

    sig { returns(::Billing::Types::Account) }
    attr_reader :target

    # target     - billable entity (User/Org/Business) making the manual credit card payment
    # purpose    - optional Symbol purpose of the payment (e.g. :general or :sponsors)
    # invoice_id - optional String Zuora invoice id this manual payment is collecting for. Its
    #              positive line item identifies the subscribable product being paid for (see
    #              #invoice_product).
    sig { params(target: ::Billing::Types::Account, purpose: T.nilable(Symbol), invoice_id: T.nilable(String)).void }
    def initialize(target:, purpose: nil, invoice_id: nil)
      @target  = target
      @purpose = purpose
      @invoice_id = invoice_id
    end

    # Get the amount due, optionally narrowed by specific purpose
    #
    # purpose - Optional Symbol purpose of the payment (e.g. :general or :sponsors)
    #
    # Returns a Billing::Money instance
    sig { params(purpose: T.nilable(Symbol)).returns(Billing::Money) }
    def balance_due(purpose: nil)
      invoices = if purpose
        invoices_due_for_purpose(purpose)
      else
        invoices_due
      end

      sum_in_dollars = invoices.sum(&:balance)
      Billing::Money.new(sum_in_dollars * 100)
    end

    # Get the Zuora invoice numbers for a specific purpose
    #
    # purpose - Symbol purpose of the payment relating to PlanSubscription purpose (e.g. :general or :sponsors)
    #
    # Returns an Array of String Zuora invoice numbers (e.g. ["INV001", "INV002"])
    sig { params(purpose: T.nilable(Symbol)).returns(T::Array[String]) }
    def invoice_numbers(purpose:)
      invoices_due_for_purpose(purpose).map(&:invoice_number)
    end

    # Does this manual payment require multiple separate payments due to our Zuora configuration?
    #
    # Sponsorships and other GitHub items require different payment gateways in order to separate funds.
    #
    # Returns a Boolean
    sig { returns(T::Boolean) }
    def requires_separate_payments?
      balance_due(purpose: :sponsors).positive? && balance_due(purpose: :general).positive?
    end

    # Payment due date
    #
    # Returns a Date or nil
    sig { returns(T.nilable(Date)) }
    def due_date
      target.manual_payment_due_date&.to_date
    end

    # Purpose of the payment
    #
    # Returns a Symbol (:sponsors or :general)
    sig { returns(T.nilable(Symbol)) }
    def purpose
      return @purpose if @purpose.present?

      return nil unless balance_due.positive?
      return nil if requires_separate_payments?

      balance_due(purpose: :sponsors).positive? ? :sponsors : :general
    end

    sig { returns(T::Boolean) }
    def single_payment?
      purpose.present?
    end

    # The subscribable product this manual payment is paying for, derived from the invoice supplied
    # at construction (its positive line item).
    #
    # This is product-agnostic: it returns whichever subscribable Billing::ProductUUID the invoice's
    # positive line item corresponds to, leaving any product-specific handling to callers. It is used
    # to finalize a Copilot plan change after a manual (India RBI) payment succeeds, without relying
    # on the asynchronous payment_processed webhook.
    #
    # Returns a Billing::ProductUUID, or nil when there is no invoice, the invoice does not belong to
    # the target, or no positive line item matches a subscribable product.
    sig { returns(T.nilable(Billing::ProductUUID)) }
    memoize def invoice_product
      # Only derive a product when this manual payment is scoped to a specific invoice. Outside the
      # India RBI upgrade flow a single payment can cover multiple invoices, so attributing it to one
      # product would be misleading.
      return nil if @invoice_id.blank?

      invoice = paid_invoice
      return nil unless invoice

      charge_ids = positive_charge_ids(invoice)
      return nil if charge_ids.empty?

      Billing::ProductUUID.subscribable.detect do |product_uuid|
        (product_uuid.zuora_product_rate_plan_charge_ids.values.flatten & charge_ids).any?
      end
    end

    private

    # The Zuora invoice this manual payment is collecting for, scoped to the target's account, or nil
    # when no invoice id was supplied or the invoice does not belong to the target.
    sig { returns(T.nilable(Billing::Zuora::Invoice)) }
    def paid_invoice
      return nil unless GitHub.billing_enabled?

      invoice_id = @invoice_id
      return nil if invoice_id.blank?

      zuora_account_id = target.customer&.zuora_account_id
      return nil if zuora_account_id.blank?

      invoice = Billing::Zuora::Invoice.new(invoice_id)
      return nil unless invoice.account_id == zuora_account_id

      invoice
    end

    sig { params(invoice: Billing::Zuora::Invoice).returns(T::Array[String]) }
    def positive_charge_ids(invoice)
      charge_ids = invoice.invoice_items.filter_map do |item|
        next unless item.charge_amount.positive?

        item.product_rate_plan_charge_id
      end
      charge_ids.uniq
    end

    sig { returns(T::Array[Billing::Zuora::Invoice]) }
    memoize def invoices_due
      return [] unless GitHub.billing_enabled?

      zuora_account_id = target.customer&.zuora_account_id
      return [] unless zuora_account_id.present?

      Billing::Zuora::Invoice.open_invoices_for_account(zuora_account_id, posted_only: true)
    end

    sig { params(purpose: T.nilable(Symbol)).returns(T::Array[T.untyped]) }
    def invoices_due_for_purpose(purpose)
      return invoices_due unless purpose.present?

      # An invoice-scoped manual payment covers a single invoice for a single product, so we don't
      # attempt per-purpose attribution (which relies on subscription lookups that may not resolve for
      # the scoped invoice and would otherwise drop its balance to zero). We treat it as a single
      # :general payment so the full balance is reflected for that purpose and excluded from :sponsors.
      if @invoice_id.present?
        return purpose == :general ? invoices_due : []
      end

      invoices_due.select do |invoice|
        subscription_number = invoice.subscription_number_from_billable_line_items
        next if subscription_number.nil?

        purpose_for(subscription_number: subscription_number) == purpose
      end
    end

    sig { returns(ActiveRecord::Associations::CollectionProxy) }
    memoize def plan_subscriptions
      target.plan_subscriptions
    end

    sig { params(subscription_number: String).returns(Symbol) }
    def purpose_for(subscription_number:)
      purpose = purpose_by_subscription_number[subscription_number]
      return purpose if purpose.present?

      purpose = T.must(Billing::Zuora::Subscription.find(subscription_number)).purpose
      purpose_by_subscription_number[subscription_number] = purpose

      purpose
    end

    sig { returns(T::Hash[String, Symbol]) }
    def purpose_by_subscription_number
      @purpose_by_subscription_number ||= T.let(plan_subscriptions.each_with_object({}) do |subscription, hsh|
        hsh[subscription.zuora_subscription_number] = subscription.purpose.to_sym
      end, T.nilable(T::Hash[String, Symbol]))
    end
  end
end
