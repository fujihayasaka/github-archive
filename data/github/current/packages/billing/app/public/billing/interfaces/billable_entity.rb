# typed: strict
# frozen_string_literal: true

module Billing
  module Interfaces
    module BillableEntity
      extend T::Helpers

      interface!

      sig { abstract.returns(T::Boolean) }
      def billed_via_billing_platform?; end

      sig { abstract.returns(T::Boolean) }
      def has_billing_record?; end

      sig { abstract.returns(T::Boolean) }
      def invoiced?; end

      sig { abstract.returns(T::Boolean) }
      def free_plan?; end

      sig { abstract.returns(T::Boolean) }
      def paid_plan?; end

      sig { abstract.returns(T::Set[String]) }
      def auto_pay_reasons; end

      sig do
        abstract.params(
          feature: Symbol,
          visibility: T.nilable(T.any(Symbol, String)),
          org: T::Boolean,
          feature_flag: T.nilable(T.any(Symbol, String)),
          fallback_to_free: T::Boolean
        ).returns(T::Boolean)
      end
      def plan_supports?(feature, visibility: nil, org: false, feature_flag: nil, fallback_to_free: false); end
    end
  end
end
