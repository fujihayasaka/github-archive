# typed: strict
# frozen_string_literal: true

module Billing
  class CreateAuthorizationBillingTransactionJob < BillingJob
    extend T::Sig

    include GitHub::Billing::ZuoraRateLimitHandler

    queue_as :create_authorization_hold

    retry_on_dirty_exit
    (Billing::Zuora::RETRYABLE_ERRORS + Billing::Braintree::RETRYABLE_ERRORS).each do |error|
      retry_on(error, wait: :polynomially_longer) do |_job, error|
        GitHub.dogstats.increment(
          "billing.create_authorization_billing_transaction_job.failed",
          tags: ["error:#{error.class.name}"],
        )
        Failbot.report(error, { "gh.job.name" => CreateAuthorizationBillingTransactionJob.name })
      end
    end

    rescue_from(Zuorest::TooManyRequestsError) do |error|
      T.bind(self, CreateAuthorizationBillingTransactionJob)

      zuora_rate_limit_handler(self, error)
    end

    class Metrics < T::Struct
      prop :amount_in_cents, Integer
      prop :declined, T::Boolean
      prop :entity, T.any(User, Business)
      prop :response_code, String
      prop :response_message, String
      prop :success, T::Boolean
      prop :transaction_id, T.nilable(String)

      prop :billing_attempts_reset, T::Boolean, default: false
      prop :billing_disabled_reason_updated, T::Boolean, default: false
      prop :billing_locked, T::Boolean, default: false
      prop :billing_unlocked, T::Boolean, default: false

      prop :origin, T.nilable(String)
    end

    class DontCallMeFromOutsideTheCode < StandardError; end
    class MissingPaymentMethodError < StandardError; end

    sig do
      params(
        entity_id: Integer,
        amount_in_cents: Integer,
        is_business: T::Boolean,
        unlock_billing_on_success: T::Boolean,
        reset_billing_attempts_when_unlocked: T::Boolean,
        skip_account_age_check: T::Boolean,
        origin: T.nilable(String)
      ).void
    end
    def perform(entity_id:, amount_in_cents:, is_business:, unlock_billing_on_success: false, reset_billing_attempts_when_unlocked: false, skip_account_age_check: false, origin: "somewhere")
      return unless entity = is_business ? Business.find_by(id: entity_id) : User.find_by(id: entity_id)

      if origin == "somewhere"
        raise DontCallMeFromOutsideTheCode
      end

      metrics = if entity.has_paypal_account?
        platform = :braintree
        payment_type = :paypal
        perform_paypal_auth(entity: entity, amount_in_cents: amount_in_cents, origin: origin)
      else
        platform = :zuora
        payment_type = :credit_card
        perform_credit_card_auth(entity: entity, amount_in_cents: amount_in_cents, origin: origin)
      end

      with_write do
        billing_transaction = Billing::BillingTransaction.new({
          user_id: entity.is_a?(Business) ? nil : entity.id,
          transaction_id: metrics.transaction_id,
          amount_in_cents: amount_in_cents,
          customer_id: entity.customer&.id,
          payment_type: payment_type,
          platform: platform,
          platform_transaction_id: metrics.transaction_id,
          transaction_type: :authorization,
          last_status: :authorizing,
          last_four: entity.payment_method.last_four,
        })

        if metrics.success
          billing_transaction.last_status = :authorized
          billing_transaction.save!

          # There is no scenario currently where we want to keep authorizations alive
          CancelAuthorizationBillingTransactionJob.perform_later(billing_transaction_id: T.must(billing_transaction.id))

          if unlock_billing_on_success && account_can_be_unlocked_through_authorization_success?(entity: entity)
            entity.enable!
            metrics.billing_unlocked = true

            if reset_billing_attempts_when_unlocked
              entity.reset_billing_attempts
              metrics.billing_attempts_reset = true
            end
          end
        else
          # TODO: card_error? could be processing_error which can be retried later according to the error message.
          # Do we want to mark this as declined or failed?
          billing_transaction.last_status = metrics.declined ? :processor_declined : :failed
          billing_transaction.save!

          if metrics.declined
            if entity.disabled? && !entity.disabled_reasons.include?(Billing::Public::BillingDisabledReasons::AuthorizationFailure)
              entity.customer&.update_disabled_reasons(Billing::Public::BillingDisabledReasons::AuthorizationFailure)
              metrics.billing_disabled_reason_updated = true
            elsif account_is_recent_and_non_rbi?(entity: entity, skip_account_age_check: skip_account_age_check)
              entity.disable!(reason: Billing::Public::BillingDisabledReasons::AuthorizationFailure)
              metrics.billing_locked = true
            end
          end
        end
      end

      instrument_authorization_transaction(metrics: metrics)
    end

    private

    sig do
      params(
        entity: Billing::Types::Account,
        amount_in_cents: Integer,
        origin: T.nilable(String),
      ).returns(Metrics)
    end
    def perform_credit_card_auth(entity:, amount_in_cents:, origin:)
      response = Billing::Zuora::PaymentAuthorization.create(
        payment_method_id: entity.payment_method.payment_token,
        account_id: entity.customer_zuora_account_id,
        amount: Billing::Money.new(amount_in_cents),
      )

      GitHub.logger.info(
        "Billing authorization created",
        "#{entity_id_key(entity: entity)}": entity.id,
        "code.function": __method__,
        "code.namespace": self.class.name,
        "gh.account.type": entity.business? ? "business" : "user",
        "gh.billing.authorization.amount_in_cents": amount_in_cents,
        "gh.billing.authorization.origin": origin,
        "gh.billing.create_authorization.success": response.success?,
        "gh.billing.zuora.payment_authorization.gateway_order_id": response.gateway_order_id,
        "gh.billing.zuora.payment_authorization.parsed_error_code": response.parsed_error_code,
        "gh.billing.zuora.payment_authorization.parsed_processor_response_code": response.parsed_processor_response_code,
        "gh.billing.zuora.payment_authorization.parsed_processor_response_message": response.parsed_processor_response_message,
        "gh.billing.zuora.payment_authorization.payment_gateway_response": response.payment_gateway_response.to_json,
        "gh.billing.zuora.payment_authorization.process_id": response.process_id,
        "gh.billing.zuora.payment_authorization.reasons": response.reasons.to_json,
        "gh.billing.zuora.payment_authorization.request_id": response.request_id,
        "gh.billing.zuora.payment_authorization.result_code": response.result_code,
        "gh.billing.zuora.payment_authorization.result_message": response.result_message,
        "gh.billing.zuora.payment_authorization.success": response.success?,
        "gh.billing.zuora.payment_authorization.transaction_id": response.transaction_id,
      )

      Metrics.new(
        amount_in_cents: amount_in_cents,
        declined: response.card_error?,
        entity: entity,
        origin: origin,
        response_code: response.parsed_processor_response_code,
        response_message: response.parsed_processor_response_message,
        success: response.success?,
        transaction_id: response.transaction_id,
      )
    end

    sig do
      params(
        entity: Billing::Types::Account,
        amount_in_cents: Integer,
        origin: T.nilable(String),
      ).returns(Metrics)
    end
    def perform_paypal_auth(entity:, amount_in_cents:, origin:)
      customer_response = ::Braintree::Customer.find(entity.customer_zuora_account_id)
      payment_method = customer_response.payment_methods.find(&:default?)

      raise MissingPaymentMethodError unless payment_method

      auth_response = ::Braintree::Transaction.sale({
        amount: amount_in_cents / 100,
        payment_method_token: payment_method.token
      })

      response_code = auth_response.transaction&.processor_response_code || ""
      response_message = auth_response.success? ? auth_response.transaction.status : auth_response.message

      GitHub.logger.info(
        "Billing authorization created",
        "#{entity_id_key(entity: entity)}": entity.id,
        "code.function": __method__,
        "code.namespace": self.class.name,
        "gh.account.type": entity.business? ? "business" : "user",
        "gh.billing.authorization.amount_in_cents": amount_in_cents,
        "gh.billing.authorization.origin": origin,
        "gh.billing.create_authorization.success": auth_response.success?,
        "gh.billing.paypal.payment_authorization.success": auth_response.success?,
        "gh.billing.paypal.payment_authorization.transaction_id": auth_response.transaction&.id,
        "gh.billing.paypal.payment_authorization.parsed_processor_response_code": response_code,
        "gh.billing.paypal.payment_authorization.parsed_processor_response_message": response_message,
      )

      Metrics.new(
        amount_in_cents: amount_in_cents,
        declined: !auth_response.success? && auth_response&.transaction&.status == "processor_declined",
        entity: entity,
        origin: origin,
        response_code: response_code,
        response_message: response_message,
        success: auth_response.success?,
        transaction_id: auth_response.transaction&.id,
      )
    end

    sig { params(metrics: Metrics).void }
    def instrument_authorization_transaction(metrics:)
      GitHub.dogstats.increment("billing.authorization_created", tags: [
        "amount_in_cents:#{metrics.amount_in_cents}",
        "billing_attempts_reset:#{metrics.billing_attempts_reset}",
        "billing_disabled_reason_updated:#{metrics.billing_disabled_reason_updated}",
        "billing_locked:#{metrics.billing_locked}",
        "billing_unlocked:#{metrics.billing_unlocked}",
        "legacy:false",
        "origin:#{metrics.origin}",
        "success:#{metrics.success}",
      ])

      entity = metrics.entity
      GlobalInstrumenter.instrument("billing.authorization_transaction_created", {
        account_type: entity.business? ? "business" : "user",
        account: entity,
        authorization_amount_in_cents: metrics.amount_in_cents,
        billing_locked: metrics.billing_locked,
        billing_unlocked: metrics.billing_unlocked,
        declined: metrics.declined,
        payment_method: entity.payment_method,
        processor_response_code: metrics.response_code,
        processor_response: metrics.response_message,
        success: metrics.success,
      })
    end

    sig { params(entity: Billing::Types::Account, skip_account_age_check: T::Boolean).returns(T::Boolean) }
    def account_is_recent_and_non_rbi?(entity:, skip_account_age_check: false)
      return false if entity.customer&.requires_manual_transactions?
      return true if skip_account_age_check || account_is_less_than_or_equal_to_30_days_old?(entity: entity)
      false
    end

    sig { params(entity: Billing::Types::Account).returns(T::Boolean) }
    def account_is_less_than_or_equal_to_30_days_old?(entity:)
      oldest_owner_age = TrustTiers::TierDetails.new(entity).oldest_owner_age
      return true if oldest_owner_age.after?(31.days.ago)
      false
    end

    sig { params(entity: Billing::Types::Account).returns(T::Boolean) }
    def account_can_be_unlocked_through_authorization_success?(entity:)
      return false unless entity.customer.present?
      return false unless entity.disabled?

      # If there is another reason for billing being disabled, that reason overrides authorization failure
      authorization_is_only_reason_for_account_being_disabled = entity.disabled_reasons.size == 1 && entity.billing_disabled_by_authorization_failure?
      disabled_without_reason = entity.disabled_reasons.empty?

      authorization_is_only_reason_for_account_being_disabled || disabled_without_reason
    end

    sig { params(entity: Billing::Types::Account).returns(String) }
    def entity_id_key(entity:)
      entity.business? ? "gh.business.id" : "gh.user.id"
    end
  end
end
