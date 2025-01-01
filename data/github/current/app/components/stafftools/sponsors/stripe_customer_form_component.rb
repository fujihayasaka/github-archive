# typed: true
# frozen_string_literal: true

class Stafftools::Sponsors::StripeCustomerFormComponent < ApplicationComponent
  # org - an Organization
  def initialize(org:)
    @org = org
  end

  private

  attr_reader :org

  def render?
    GitHub.sponsors_enabled? && org.present? && org.organization? && logged_in?
  end

  memoize def stripe_customer_id
    org.stripe_customer_id
  end
end
