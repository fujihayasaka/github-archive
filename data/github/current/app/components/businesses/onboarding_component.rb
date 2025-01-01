# typed: true
# frozen_string_literal: true

class Businesses::OnboardingComponent < ApplicationComponent
  include BusinessesHelper

  attr_reader :business

  def initialize(business:)
    @business = business
  end

  # @return [Boolean]
  def render?
    show_onboarding_experience?(business) || show_org_upgrade_onboarding_experience?(business)
  end

  memoize def display_header?
    return false if business.seats_plan_basic?
    return false if emu_first_admin?

    business.trial? || business.upgraded_from_organization?
  end

  memoize def emu_first_admin?
    return false unless business.enterprise_managed?

    current_user && current_user == business.find_first_emu_owner
  end

  memoize def show_digital_front_door_header?
    return false unless business.trial?
    return false unless business.metered_ghe?
    business.dfd_trial?
  end
end
