# typed: true
# frozen_string_literal: true

module Billing
  module Stafftools
    class BlockPaymentMethod
      sig { returns(String) }
      attr_reader :card_fingerprint

      sig { params(card_fingerprint: String, actor: User, reason: T.nilable(String), consequence: T.nilable(BlacklistedPaymentMethod::Consequence), apply_to_current_users: T::Boolean).void } # rubocop:disable Naming/InclusiveLanguage
      def initialize(card_fingerprint:, actor:, reason: nil, consequence: nil, apply_to_current_users: true)
        @card_fingerprint = card_fingerprint
        @actor = actor
        @reason = reason
        @consequence = consequence
        @apply_to_current_users = apply_to_current_users
      end

      sig { void }
      def call
        payment_method = PaymentMethod.with_card_fingerprint(card_fingerprint).first!

        BlacklistedPaymentMethod.create_for_all_accounts(payment_method, reason: @reason, consequence: @consequence, actor: @actor, execute_consequences: @apply_to_current_users) # rubocop:disable Naming/InclusiveLanguage
      end
    end
  end
end
