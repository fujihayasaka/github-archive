# typed: true
# frozen_string_literal: true

module Billing
  module Stafftools
    class BlockCardFingerprintAndSuspendUsers
      extend T::Sig

      sig { returns(String) }
      attr_reader :card_fingerprint

      sig { params(card_fingerprint: String, actor: User, reason: T.nilable(String)).void }
      def initialize(card_fingerprint:, actor:, reason: nil)
        @card_fingerprint = card_fingerprint
        @actor = actor
        @reason = reason
      end

      sig { void }
      def call
        PaymentMethod.transaction do
          payment_method = PaymentMethod.with_card_fingerprint(card_fingerprint).first!
          BlacklistedPaymentMethod.create_from_user_and_payment_method(payment_method.user, payment_method, reason: @reason, actor: @actor) # rubocop:disable Naming/InclusiveLanguage

          PaymentMethod.with_card_fingerprint(card_fingerprint).each do |payment_method|
            payment_method.user&.suspend("suspended due to reused card fingerprint")
          end
        end
      end
    end
  end
end
