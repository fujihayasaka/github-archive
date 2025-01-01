# typed: true
# frozen_string_literal: true

class Stafftools::Billing::SponsorsAddCreditBalanceModalComponent < ApplicationComponent
  include Stafftools::BillingHelper

  # sponsor - a User or Organization
  def initialize(sponsor:)
    @sponsor = sponsor
  end

  memoize def render?
    GitHub.sponsors_enabled? && sponsor&.sponsors_invoiced?
  end

  private

  attr_reader :sponsor
end
