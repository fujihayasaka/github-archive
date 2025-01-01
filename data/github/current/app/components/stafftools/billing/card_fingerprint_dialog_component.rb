# typed: strict
# frozen_string_literal: true

module Stafftools
  module Billing
    class CardFingerprintDialogComponent < ApplicationComponent
      extend T::Sig

      class Action < T::Enum
        enums do
          Block = new("block")
          Unblock = new("unblock")
        end
      end

      sig { returns(String) }
      attr_reader :card_fingerprint

      sig { params(card_fingerprint: String, action: Action).void }
      def initialize(card_fingerprint:, action:)
        @card_fingerprint = card_fingerprint
        @action = action
      end

      sig { returns(String) }
      def action
        @action.serialize
      end

      sig { returns(T::Boolean) }
      def render?
        GitHub.billing_enabled?
      end
    end
  end
end
