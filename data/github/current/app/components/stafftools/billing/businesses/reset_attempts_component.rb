# typed: true
# frozen_string_literal: true

class Stafftools::Billing::Businesses::ResetAttemptsComponent < ApplicationComponent
  attr_reader :business

  def initialize(business:)
    @business = business
  end

  private

  def render?
    GitHub.billing_enabled?
  end
end
