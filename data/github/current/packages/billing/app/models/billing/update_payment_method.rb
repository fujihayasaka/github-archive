# typed: strict
# frozen_string_literal: true

module Billing
  class UpdatePaymentMethod

    include GitHub::Memoizer

    Error = Class.new(StandardError)

    sig { returns(T.nilable(GitHub::Billing::Result)) }
    attr_accessor :response

    METERED_PRODUCTS = T.let(%w[actions packages shared_storage codespaces git_lfs].freeze, T::Array[String])

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
      @payment_details = T.let(payment_details.reverse_merge!(charge: true), T::Hash[Symbol, T.untyped])
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

        # Experiment with delays after updating a payment method to workaround internal Zuora errors
        (1..10).each do |i|
          sleep i if @target.feature_enabled?("billing_delay_#{i}s_after_update_payment_method".to_sym)
        end unless Rails.env.test? # rubocop:disable GitHub/DoNotBranchOnRailsEnv

        if @response.success?
          log_outstanding_balance

          if @payment_details.has_key?(:billing_extra)
            @target.update_attribute(:billing_extra, @payment_details[:billing_extra])
          end

          if @payment_details.has_key?(:vat_code)
            customer.update_attribute(:vat_code, @payment_details[:vat_code])
          end

          # This will create an external subscription if needed
          # We wait a bit to give Zuora time to fully process the payment method update
          BillingChargeJob.set(wait: 1.minute).perform_later(@target) if @payment_details[:charge]

          return self unless @payment_details[:unlock_billing] && @target.disabled?

          # For accounts that are locked:
          #  1. If they SHOULD be unlocked, then we will unlock them immediately.
          #  2. If they CAN be unlocked, then we will perform an authorization which upon success will unlock them.
          if target_needs_billing_unlocked?
            @target.unlock_billing!
          elsif should_perform_authorization?
            log_perform_authorization
            Billing::CreateAuthorizationBillingTransactionJob.set(wait: 5.seconds).perform_later(
              entity_id: T.must(@target.id),
              amount_in_cents: threshold_amount_in_cents,
              unlock_billing_on_success: true,
              reset_billing_attempts_when_unlocked: true,
              is_business: @target.is_a?(Business),
              origin: self.class.name
            )
            # Keep track of the number of times an account is going through this flow to keep tabs on any potential abuse
            set_authorization_count(authorization_count + 1)
          end
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

    # Private: Determines whether the target needs its billing unlocked. If it's a Business that has
    # been disabled due to failed recurring charge, its billing should be unlocked without checking
    # if it should be disabled. This is because, considering the fact that Business accounts don't
    # have supported multiple plans, the disabled state is synonymous with being in a downgraded
    # free plan state, while the enabled state is synonymous with being in an upgraded business_plus
    # plan state. Hence, there's no logic to never disable a Business downgraded due to recurring
    # charge in the Business#never_disable? method. The logic hasn't been added there to avoid an
    # unexpected toggle effect on the plan of the Business when Business#enable_or_disable! is
    # called. Otherwise, the need to have target's billing unlocked should be determined based on
    # whether it should be disabled.
    sig { returns(T::Boolean) }
    memoize def target_needs_billing_unlocked?
      if @target.is_a?(Business) && @target.disabled_due_to_failed_recurring_charge?
        true
      else
        !@target.should_disable?
      end
    end

    # Whether or not we should perform an authorization that will unlock the target upon success.
    sig { returns(T::Boolean) }
    memoize def should_perform_authorization?
      # Skip authorization if an external subscription doesn't exist and we know that we will be synchronizing
      # paid products. In that scenario, the BillingChargeJob will attempt a charge after creating a new subscription.
      return false if !@target.external_subscription? && @target.payment_amount(include_metered_usage: false) > 0

      true
    end

    sig { void }
    def log_perform_authorization
      GitHub.dogstats.increment("billing.update_payment_method.perform_authorization",
        tags: ["authorization_count:#{authorization_count}"])

      data = {
        "code.namespace" => self.class.name,
        "code.function" => __method__,
        "gh.billing.billable_entity.authorization_count" => authorization_count,
        "gh.billing.billable_entity.billed_on" => @target.billed_on,
        "gh.billing.billable_entity.billing_attempts" => @target.billing_attempts,
        "gh.billing.billable_entity.id" => @target.id,
        "gh.billing.billable_entity.should_disable" => @target.should_disable?,
        "gh.billing.billable_entity.type" => @target.class.name,
        "gh.billing.customer.disabled_reasons" => customer.disabled_reasons.join(","),
        "gh.billing.customer.id" => customer.id,
        "gh.billing.customer.requires_manual_transactions" => customer.requires_manual_transactions?,
      }

      if @target.is_a?(Business)
        data["gh.business.slug"] = @target.slug
      else
        data["gh.user.login"] = @target.display_login
      end

      GitHub.logger.info(data)
    end

    # The Billing::Kv.store key used to store the authorization count
    sig { returns(String) }
    memoize def authorization_count_key
      target_type = @target.business? ? "business" : "user"
      "billing_auth_unlock_#{target_type}_#{@target.id}"
    end

    # The number of times this target has gone through the authorization flow
    sig { returns(Integer) }
    memoize def authorization_count
      Billing::Kv.store.get(authorization_count_key).value!.to_i
    end

    # Updates the authorization count in Billing::Kv.store
    sig { params(count: Integer).void }
    def set_authorization_count(count)
      Billing::Kv.store.set(authorization_count_key, count.to_s, expires: 90.days.from_now)
    end

    # Authorization amount is based on the amount of metered usage the account has incurred
    # or copilot seats if it's a copilot org:
    #  - If untrusted copilot organization, amount proportional to # of copilot seats, up to $190
    #  - Over $500.00 of usage: $100 should be authorized
    #  - Over $0.00 of usage: $20 should be authorized
    #  - No usage: $1.00 should be authorized
    sig { returns(Integer) }
    def threshold_amount_in_cents
      authorization_amount_options = []

      if @target.organization? \
          && @target.feature_enabled?(:copilot_auth_on_payment_method_update) \
          && TrustTiers::Tier.for_billable_owner(@target).tier >= TrustTiers::Tier::NEUTRAL
        copilot_organization = ::Copilot::Organization.new(T.cast(@target, Organization))
        authorization_amount_options.push(copilot_organization.auth_and_capture_amount_in_cents)
      end

      if total_metered_usage_amount_in_cents >= 50000
        authorization_amount_options.push(10000)
      elsif total_metered_usage_amount_in_cents > 0
        authorization_amount_options.push(2000)
      else
        authorization_amount_options.push(100)
      end

      authorization_amount_options.compact.max
    end

    sig { returns(Integer) }
    def total_metered_usage_amount_in_cents
      usage_checker.total_usage_in_cents
    end

    sig { returns(Billing::UsageChecker) }
    memoize def usage_checker
      Billing::UsageChecker.new(
        account: @target,
        product_names: METERED_PRODUCTS
      )
    end
  end
end
