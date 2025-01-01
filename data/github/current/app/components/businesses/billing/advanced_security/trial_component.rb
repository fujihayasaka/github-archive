# typed: true
# frozen_string_literal: true
class Businesses::Billing::AdvancedSecurity::TrialComponent < ApplicationComponent

  sig { returns Business }
  attr_reader :business

  sig { params(business: Business).void }
  def initialize(business:)
    @business = business
  end

  memoize def show_purchase_menu_item?
    business.eligible_for_self_serve_advanced_security?(skip_shared_checks: true)
  end

  sig { returns(T.nilable(String)) }
  def expires_at
    business.advanced_security_subscription_change&.active_on&.strftime("%b %d, %Y")
  end

  def used_seats
    license.consumed_seats
  end

  private

  def license
    license = business.advanced_security_license
  end
end
