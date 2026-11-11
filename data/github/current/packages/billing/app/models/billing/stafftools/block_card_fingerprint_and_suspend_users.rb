# typed: true
# frozen_string_literal: true

module Billing
  module Stafftools
    class BlockCardFingerprintAndSuspendUsers

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
        payment_method = PaymentMethod.with_card_fingerprint(card_fingerprint).first!
        return unless payment_method.owner

        PaymentMethod.transaction do
          BlacklistedPaymentMethod.create_from_account_and_payment_method(payment_method.owner, payment_method, reason: @reason, actor: @actor) # rubocop:disable Naming/InclusiveLanguage

          PaymentMethod.with_card_fingerprint(card_fingerprint).each do |payment_method|
            payment_method.owner.suspend("suspended due to reused card fingerprint")
          end
        end
      end
    end
  end
end
