# typed: strict
# frozen_string_literal: true

module Codespaces
  module Access
    class AllowedResult
      extend T::Sig

      sig { returns(Symbol) }
      attr_reader :reason

      DISALLOW_PAYMENT_METHOD = :DISALLOW_PAYMENT_METHOD
      DISALLOW_SPENDING_LIMIT = :DISALLOW_SPENDING_LIMIT
      DISALLOW_ENTITLEMENTS   = :DISALLOW_ENTITLEMENTS
      DISALLOW_BILLING        = :DISALLOW_BILLING
      DISALLOW_MACHINE_POLICY = :DISALLOW_MACHINE_POLICY
      DISALLOW_IMAGE_POLICY   = :DISALLOW_IMAGE_POLICY
      ALLOWED = :allowed
      BILLING_REASONS = T.let([DISALLOW_PAYMENT_METHOD, DISALLOW_SPENDING_LIMIT, DISALLOW_ENTITLEMENTS, DISALLOW_BILLING], T::Array[Symbol])

      sig { params(reason: T.untyped).void }
      def initialize(reason)
        @reason = T.let(reason, Symbol)
      end

      sig { returns(T::Boolean) }
      def allowed?
        @reason == ALLOWED
      end

      sig { returns(T::Boolean) }
      def disallowed?
        @reason != ALLOWED
      end

      sig { returns(T::Boolean) }
      def disallowed_by_machine_policy?
        @reason == DISALLOW_MACHINE_POLICY
      end

      sig { returns(T::Boolean) }
      def disallowed_by_image_policy?
        @reason == DISALLOW_IMAGE_POLICY
      end

      sig { returns(T::Boolean) }
      def disallowed_by_spending_limit?
        @reason == DISALLOW_SPENDING_LIMIT
      end

      sig { returns(T::Boolean) }
      def disallowed_by_entitlements?
        @reason == DISALLOW_ENTITLEMENTS
      end

      sig { returns(T::Boolean) }
      def disallowed_by_billing?
        BILLING_REASONS.include?(@reason)
      end

      sig { returns(T::Boolean) }
      def disallowed_by_payment_method?
        @reason == DISALLOW_PAYMENT_METHOD
      end

      sig { returns(T.attached_class) }
      def self.allowed
        self.new(ALLOWED)
      end
    end
  end
end
