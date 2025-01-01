# typed: strict
# frozen_string_literal: true

class User
  class CardConverter
    extend T::Sig

    include GitHub::Memoizer

    class ConvertError < StandardError; end

    sig { params(target: User).void }
    def initialize(target)
      @target = target
    end

    # Public: Can target be converted to card based billing?
    sig { returns(T::Boolean) }
    def convertable?
      reason_not_convertable.blank?
    end

    # Public: Switch to credit card billing
    sig { params(actor: User).returns(T::Boolean) }
    def convert(actor:)
      raise ConvertError.new(reason_not_convertable) unless convertable?

      target.update(billing_type: User::BillingDependency::CARD_BILLING_TYPE)
      target.customer&.update(zuora_account_id: nil, zuora_account_number: nil)
      target.plan_subscription&.clear_external_subscription_references

      instrument(actor: actor)

      true
    end

    private

    sig { returns(User) }
    attr_reader :target

    sig { params(actor: User).void }
    def instrument(actor:)
      GlobalInstrumenter.instrument(
        "billing.change_billing_type",
        old_billing_type: target.attribute_before_last_save(:billing_type),
        billing_type: target.billing_type,
        user: target,
        actor: actor,
      )
    end

    sig { returns(T.nilable(String)) }
    memoize def reason_not_convertable
      return "@#{target} is not invoiced." unless target.invoiced?

      if GitHub.sponsors_enabled?
        if target.has_paypal_account? && target.actively_recurring_sponsor?
          return "@#{target} has PayPal and an active, recurring sponsorship; either cancel the sponsorship(s) or " \
            "remove the PayPal payment method before switching to self-serve billing."
        end
      end

      nil
    end
  end
end
