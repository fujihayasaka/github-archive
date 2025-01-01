# typed: true
# frozen_string_literal: true

class Businesses::CopilotGettingStartedComponent < ApplicationComponent
  attr_reader :business

  def initialize(business:, dfd_trial: false)
    @business = business
    @dfd_trial = dfd_trial
  end

  private

  memoize def guide_hidden?
    current_user.dismissed_business_notice?(
      BusinessesHelper::COPILOT_ONBOARDING_NOTICE_NAME,
      business_id: business.id
    )
  end

  memoize def for_owners?
    business.owner?(current_user)
  end

  def dfd_trial?
    @dfd_trial
  end
end
