# typed: strict
# frozen_string_literal: true

module Billing
  class UpdatePaymentMethod

    include GitHub::Memoizer

    Error = Class.new(StandardError)

    sig { returns(T.nilable(GitHub::Billing::Result)) }
    attr_accessor :response

    # Public: Updates payment method details of an existing customer.
    # This also tries to charge the new card (or paypal account) if the user
    # account is disabled or its billed_on is in the past.
    #
    # target          - A User or Business object who's credit card data we're updating.
    # payment_details - A Hash of payment details:
    #                   :zuora_payment_method_id - String Zuora Hosted Payment Pages payment method ID
    #                   :charge        - Boolean whether to attempt a recurring charge with this update. Default: true
    #                   :billing_extra - String extra billing information.
    #                   :vat_code      - String VAT identification number
    #                   :paypal_nonce  - String nonce representing a paypal account (optional).
    #                   :credit_card   - A Hash of potentially encrypted CC info, including:
    #                     * :number           - CC number as a String.
    #                     * :expiration_month - Expiration month as a String of form MM
    #                     * :expiration_year  - Expiration year as a String of form YY
    #                     * :cvv              - CVV as a String (e.g. "420")
    #                   :billing_address  - The billing address as a Hash of optionally encrypted CC info
    #                     * :country_code_alpha3 - Country as a String
    #                     * :region              - Region as a String
    #                     * :postal_code         - Postal code as a String
    # purpose         - Symbol indicating the purpose of the customer whose payment method should be updated,
    #                   :general or :sponsors
    #
    # Returns a GitHub::Billing::Result object, indicating
    # success or failure, the user that was updated and an error message if the
    # customer's credit card could not be updated.
    sig { params(target: ::Billing::Types::Account, payment_details: T::Hash[Symbol, T.untyped], purpose: T.any(Symbol, String), skip_synchronization: T::Boolean).returns(::Billing::UpdatePaymentMethod) }
    def self.perform(target, payment_details, purpose: Customer::DEFAULT_PURPOSE, skip_synchronization: false)
      new(target, payment_details, purpose: purpose, skip_synchronization: skip_synchronization).perform
    end

    sig { params(target: ::Billing::Types::Account, payment_details: T::Hash[Symbol, T.untyped], purpose: T.any(Symbol, String), skip_synchronization: T::Boolean).void }
    def initialize(target, payment_details, purpose: Customer::DEFAULT_PURPOSE, skip_synchronization: false)
      @target  = target
      @purpose = purpose
      @customer = T.let(T.must(target.customer_for(purpose)), Customer)
      @payment_details = T.let(payment_details, T::Hash[Symbol, T.untyped])
      @skip_synchronization = skip_synchronization
      @response = T.let(nil, T.nilable(GitHub::Billing::Result))
    end

    sig { returns(T.self_type) }
    def perform
      Failbot.push("gh.target.id" => @target.id)

      if paypal_switch_error_message.present?
        @response = GitHub::Billing::Result.failure(paypal_switch_error_message)
        return self
      end

      if customer.payment_method.nil?
        payment_method = customer.build_payment_method(
            payment_processor_type: PaymentMethod.zuora_processor_slug,
            payment_processor_customer_id: customer.zuora_account_id,
            payment_token: PaymentMethod::PAYMENT_TOKEN_CLEARED,
        )
        payment_method.user = @target if !(@target.is_a?(Business) || @target.business)

        unless payment_method.save
          @response = GitHub::Billing::Result.failure("No payment method record to update.")
          return self
        end
      end

      @target.check_for_spam
      if @target.spammy?
        @response = GitHub::Billing::Result.failure("This account has been flagged. #{GitHub.support_link_text} for further information.")
      else
        @response = customer.update_payment_method_details(@payment_details)

        if @response.success?
          log_outstanding_balance

          if @payment_details.has_key?(:billing_extra)
            @target.update_attribute(:billing_extra, @payment_details[:billing_extra])
          end

          if @payment_details.has_key?(:vat_code)
            customer.update_attribute(:vat_code, @payment_details[:vat_code])
          end

          # Due to a bug in Zuora, attempting to authorize or charge a payment method immediately after
          # it has been updated can result in duplicate charges. As a crude workaround, we wait 1 minute
          # (determined experimentally) before attempting to do anything with the payment method.
          Billing::VerifyPaymentMethodJob.set(wait: 1.minute).perform_later(@target, @response.record&.token)
        end
      end

      self
    end

    private

    sig { returns(Customer) }
    attr_reader :customer

    sig { returns(T.nilable(String)) }
    memoize def paypal_switch_error_message
      return unless @payment_details[:paypal_nonce].present?
      return unless GitHub.sponsors_enabled?
      return if @purpose == :general && @target.sponsors_customer.present?

      total_recurring_sponsorships = T.unsafe(@target.active_sponsorships_as_sponsor_relation).recurring.size
      return if total_recurring_sponsorships < 1

      units = "sponsorship".pluralize(total_recurring_sponsorships)
      whose_sponsorships = @target.user? ? "your" : "@#{@target}'s"
      adjective = total_recurring_sponsorships == 1 ? "recurring" : "#{total_recurring_sponsorships} recurring"
      "You must cancel #{whose_sponsorships} #{adjective} #{units} first before you can switch to PayPal."
    end

    sig { void }
    def log_outstanding_balance
      return unless plan_subscription = @target.plan_subscription

      outstanding_balance = plan_subscription.cached_outstanding_balance_from_last_cancelled_zuora_subscription

      return unless outstanding_balance.positive?

      GitHub.dogstats.count("billing.update_payment_method.outstanding_balance", outstanding_balance,
        tags: ["purpose:#{plan_subscription.purpose}", "billable_entity_type:#{@target.class.name}", "disabled:#{@target.disabled?}"])

      data = {
        "code.namespace" => self.class.name,
        "code.function" => __method__,
        "gh.billing.billable_entity.id" => @target.id,
        "gh.billing.billable_entity.type" => @target.class.name,
        "gh.billing.plan_subscription.outstanding_balance" => outstanding_balance,
      }

      if @target.is_a?(Business)
        data["gh.business.slug"] = @target.slug
      else
        data["gh.user.login"] = @target.display_login
      end

      GitHub.logger.info(data)
    end
  end
end
