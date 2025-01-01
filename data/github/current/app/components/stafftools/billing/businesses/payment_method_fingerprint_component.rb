# typed: strict
# frozen_string_literal: true

class Stafftools::Billing::Businesses::PaymentMethodFingerprintComponent < ApplicationComponent
  sig { params(business: Business).void }
  def initialize(business:)
    @business = business
  end

  private

  sig { returns(Business) }
  attr_reader :business

  sig { returns(T::Boolean) }
  def render?
    payment_method_fingerprint.present?
  end

  sig { returns(T.nilable(String)) }
  memoize def payment_method_fingerprint
    business.payment_method&.card_fingerprint
  end
end
