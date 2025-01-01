# typed: strict
# frozen_string_literal: true

# Data object that support serialization/deserialization for use as a HTML form input value
module Sponsors
  class StripePayoutInput < T::Struct
    SEPARATOR = "|"
    extend T::Sig

    prop :account_id, String
    prop :payout_id, String

    sig { params(payout: String).returns(T.nilable(Sponsors::StripePayoutInput)) }
    def self.deserialize(payout)
      payout_id, account_id = payout.split(SEPARATOR)
      return nil unless payout_id.present? && account_id.present?
      new(account_id: account_id, payout_id: payout_id)
    end

    sig { returns String }
    def serialize
      [payout_id, account_id].join(SEPARATOR)
    end
  end
end
