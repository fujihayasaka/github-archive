# typed: true
# frozen_string_literal: true

class Businesses::EnterpriseExploreMoreComponent < ApplicationComponent
  include BusinessesHelper

  attr_reader :business

  def initialize(business:)
    @business = business
  end

  private

  memoize def render?
    business.owner?(current_user)
  end

  memoize def onboarding_experience_dismissed?
    (trial_onboarding_dismissed? && !business.trial_expired?) || copilot_onboarding_dismissed?
  end

  memoize def trial_onboarding_dismissed?
    current_user.dismissed_business_notice?(BusinessesHelper::TRIAL_ONBOARDING_NOTICE_NAME, business_id: business.id)
  end

  memoize def copilot_onboarding_dismissed?
    current_user.dismissed_business_notice?(BusinessesHelper::COPILOT_ONBOARDING_NOTICE_NAME, business_id: business.id)
  end

  def reset_onboarding_notice_name
    if trial_onboarding_dismissed?
      BusinessesHelper::TRIAL_ONBOARDING_NOTICE_NAME
    elsif copilot_onboarding_dismissed?
      BusinessesHelper::COPILOT_ONBOARDING_NOTICE_NAME
    end
  end
end
