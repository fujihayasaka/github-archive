# typed: true
# frozen_string_literal: true

class Stafftools::Billing::Businesses::RemovePaymentMethodComponent < ApplicationComponent
  def initialize(business:)
    @business = business
  end

  private

  attr_reader :business

  def render?
    business.has_valid_payment_method?(feature_type: :noncommercial)
  end
end
