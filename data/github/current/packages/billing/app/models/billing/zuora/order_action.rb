# typed: strict
# frozen_string_literal: true

class Billing::Zuora::OrderAction < T::Struct
  class ChargeOverride < T::Struct
    class BillingParams < T::Struct
      prop :bill_cycle_type, T.nilable(String), name: "billCycleType"
      prop :billing_period_alignment, T.nilable(String), name: "billingPeriodAlignment"

      sig { returns(T::Hash[Symbol, T.untyped]) }
      def to_subscribe_amend_format
        override = {}
        if bill_cycle_type = self.bill_cycle_type.presence
          override[:billCycleType] = bill_cycle_type
        end

        if billing_period_alignment = self.billing_period_alignment.presence
          override[:billingPeriodAlignment] = billing_period_alignment
        end

        override
      end
    end

    class Pricing < T::Struct
      class RecurringFlatFee < T::Struct
        prop :list_price, T.nilable(Float), name: "listPrice"

        sig { returns(T::Hash[Symbol, T.untyped]) }
        def to_subscribe_amend_format
          override = {}
          if list_price = self.list_price.presence
            override[:price] = ::Billing::Money.new(list_price * 100)
          end

          override
        end
      end

      class RecurringPerUnit < T::Struct
        prop :list_price, T.nilable(Float), name: "listPrice"
        prop :quantity, T.nilable(::Billing::Types::Numeric)

        sig { returns(T::Hash[Symbol, T.untyped]) }
        def to_subscribe_amend_format
          override = {}
          if list_price = self.list_price.presence
            override[:price] = ::Billing::Money.new(list_price * 100)
          end

          unless quantity.nil?
            override[:quantity] = quantity
          end

          override
        end
      end

      class Discount < T::Struct
        prop :discount_percentage, T.nilable(::Billing::Types::Numeric), name: "discountPercentage"
        prop :discount_amount, T.nilable(::Billing::Types::Numeric), name: "discountAmount"

        sig { returns(T::Hash[Symbol, T.untyped]) }
        def to_subscribe_amend_format
          override = {}
          if discount_percentage = self.discount_percentage.presence
            override[:discountPercentage] = discount_percentage
          end

          if discount_amount = self.discount_amount.presence
            override[:discountAmount] = discount_amount
          end

          override
        end
      end

      class UsageOverage < T::Struct
        prop :included_units, T.nilable(::Billing::Types::Numeric), name: "includedUnits"

        sig { returns(T::Hash[Symbol, T.untyped]) }
        def to_subscribe_amend_format
          override = {}

          if included_units = self.included_units.presence
            override[:includedUnits] = included_units
          end

          override
        end
      end

      sig do
        params(included_units: T.nilable(::Billing::Types::Numeric))
          .returns(T.attached_class)
      end
      def self.with_usage_overage(included_units: nil)
        new(usage_overage: UsageOverage.new(included_units: included_units))
      end

      sig do
        params(list_price: T.nilable(Float), quantity: T.nilable(::Billing::Types::Numeric))
          .returns(T.attached_class)
      end
      def self.with_recurring_per_unit(list_price: nil, quantity: nil)
        new(recurring_per_unit: RecurringPerUnit.new(
          list_price: list_price,
          quantity: quantity
        ))
      end

      sig do
        params(list_price: T.nilable(Float))
          .returns(T.attached_class)
      end
      def self.with_recurring_flat_fee(list_price: nil)
        new(recurring_flat_fee: RecurringFlatFee.new(
          list_price: list_price
        ))
      end

      sig do
        params(discount_percentage: T.nilable(::Billing::Types::Numeric),
          discount_amount: T.nilable(::Billing::Types::Numeric))
          .returns(T.attached_class)
      end
      def self.with_discount(discount_percentage: nil, discount_amount: nil)
        new(discount: Discount.new(
          discount_percentage: discount_percentage,
          discount_amount: discount_amount
        ))
      end

      sig { returns(T::Hash[Symbol, T.untyped]) }
      def to_subscribe_amend_format
        override = {}
        if recurring_flat_fee = self.recurring_flat_fee.presence
          override.merge!(recurring_flat_fee.to_subscribe_amend_format)
        end

        if recurring_per_unit = self.recurring_per_unit.presence
          override.merge!(recurring_per_unit.to_subscribe_amend_format)
        end

        if discount = self.discount.presence
          override.merge!(discount.to_subscribe_amend_format)
        end

        if usage_overage = self.usage_overage.presence
          override.merge!(usage_overage.to_subscribe_amend_format)
        end

        override
      end

      prop :discount, T.nilable(Discount)
      prop :recurring_flat_fee, T.nilable(RecurringFlatFee), name: "recurringFlatFee"
      prop :recurring_per_unit, T.nilable(RecurringPerUnit), name: "recurringPerUnit"
      prop :usage_overage, T.nilable(UsageOverage), name: "usageOverage"
    end

    const :product_rate_plan_charge_id, String, name: "productRatePlanChargeId"

    prop :billing, T.nilable(BillingParams)
    prop :custom_fields, T.nilable(T::Hash[Symbol, T.untyped]), name: "customFields"
    prop :pricing, T.nilable(Pricing)

    sig { returns(::Billing::PlanSubscription::ZuoraSubscriptionParams::ChargeOverrideParams) }
    def to_subscribe_amend_format
      override = { productRatePlanChargeId: product_rate_plan_charge_id }

      if pricing = self.pricing.presence
        override.merge!(pricing.to_subscribe_amend_format)
      end

      if billing = self.billing.presence
        override.merge!(billing.to_subscribe_amend_format)
      end

      if custom_fields = self.custom_fields.presence
        override.merge!(custom_fields)
      end

      override
    end
  end

  class SubscribeToRatePlan < T::Struct
    const :product_rate_plan_id, String, name: "productRatePlanId"
    prop :charge_overrides, T::Array[ChargeOverride], name: "chargeOverrides", default: []

    sig { returns(::Billing::PlanSubscription::ZuoraSubscriptionParams::SubscriptionRatePlanParam) }
    def to_subscribe_amend_format
      {
        productRatePlanId: product_rate_plan_id,
        chargeOverrides: charge_overrides.map(&:to_subscribe_amend_format)
      }
    end
  end

  class CreateSubscriptionParams < T::Struct
    class TermType < T::Enum
      enums do
        Termed = new("TERMED")
        Evergreen = new("EVERGREEN")
      end
    end

    class InitialTerm < T::Struct
      prop :start_date, T.nilable(String), name: "startDate"
      prop :term_type, TermType, name: "termType"
    end

    class Terms < T::Struct
      prop :initial_term, InitialTerm, name: "initialTerm"
    end

    class PaymentProfile < T::Struct
      prop :payment_gateway_id, T.nilable(String), name: "paymentGatewayId"
    end

    prop :invoice_separately, T.nilable(T::Boolean), name: "invoiceSeparately"
    prop :payment_profile, T.nilable(PaymentProfile), name: "paymentProfile"
    prop :subscribe_to_rate_plans, T::Array[SubscribeToRatePlan], name: "subscribeToRatePlans", default: []
    prop :terms, Terms, name: "terms"

    sig { params(start_date: T.nilable(Date)).returns(T.attached_class) }
    def self.evergreen(start_date: nil)
      new(
        terms: Terms.new(
          initial_term: InitialTerm.new(
            term_type: TermType::Evergreen,
            start_date: start_date.to_s.presence
          )
        )
      )
    end

    sig { params(product_rate_plan_id: String, blk: T.proc.params(plan: SubscribeToRatePlan).void).returns(T.self_type) }
    def add_rate_plan(product_rate_plan_id:, &blk)
      rate_plan = Billing::Zuora::OrderAction::SubscribeToRatePlan.new(product_rate_plan_id: product_rate_plan_id)
      yield rate_plan
      self.subscribe_to_rate_plans << rate_plan

      self
    end
  end

  class CancelSubscriptionParams < T::Struct

    class CancellationPolicy < T::Enum
      enums do
        EndOfCurrentTerm = new("EndOfCurrentTerm")
        EndOfLastInvoicePeriod = new("EndOfLastInvoicePeriod")
        SpecificDate = new("SpecificDate")
      end
    end

    sig { params(cancellation_effective_date: String).returns(T.attached_class) }
    def self.specific_date(cancellation_effective_date:)
      new(
        cancellation_policy: CancellationPolicy::SpecificDate,
        cancellation_effective_date: cancellation_effective_date,
      )
    end

    prop :cancellation_effective_date, T.nilable(String), name: "cancellationEffectiveDate"
    prop :cancellation_policy, CancellationPolicy, name: "cancellationPolicy"
  end

  class Type < T::Enum
    enums do
      CreateSubscription = new("CreateSubscription")
      CancelSubscription = new("CancelSubscription")
    end
  end

  const :type, Type
  prop :create_subscription, T.nilable(CreateSubscriptionParams), name: "createSubscription"
  prop :cancel_subscription, T.nilable(CancelSubscriptionParams), name: "cancelSubscription"

  sig { returns(T::Boolean) }
  def valid?
    serialize[type.serialize.camelize(:lower)].present?
  end

  # Define a type alias for params
  OrderActionParams = T.type_alias do
    T.any(CreateSubscriptionParams, CancelSubscriptionParams)
  end

  PARAMS_FOR_TYPE = T.let({
    Type::CreateSubscription => CreateSubscriptionParams,
    Type::CancelSubscription => CancelSubscriptionParams,
    # Add other mappings as we implement them
  }.freeze, T::Hash[Type, T::Class[OrderActionParams]])
end
