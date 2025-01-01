# typed: true
# frozen_string_literal: true

class Businesses::EmuFirstAdminGettingStartedComponent < ApplicationComponent
  attr_reader :business

  def initialize(business:)
    @business = business
  end

  private

  memoize def guide_hidden?
    current_user.dismissed_business_notice?(
      BusinessesHelper::TRIAL_ONBOARDING_NOTICE_NAME,
      business_id: business.id
    )
  end
end
