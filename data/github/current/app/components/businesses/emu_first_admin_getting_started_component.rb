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

  memoize def show_switch_account_cta?
    additional_owners.count > 0 && business.external_provider_enabled?
  end

  memoize def signon_button_text
    if additional_owners.count > 1
      "Try single sign-on as an enterprise owner"
    else
      "Continue as @#{additional_owners.first.display_login}"
    end
  end

  memoize def additional_owners
    business.find_emu_owners_except_first
  end
end
