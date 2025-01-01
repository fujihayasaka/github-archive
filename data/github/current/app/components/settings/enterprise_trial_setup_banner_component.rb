# typed: true
# frozen_string_literal: true

module Settings
  class EnterpriseTrialSetupBannerComponent < ApplicationComponent
    include BusinessesHelper

    attr_reader :business, :current_user

    def initialize(business:, current_user:)
      @business = business
      @current_user = current_user
    end

    private

    def render?
      return false unless GitHub.billing_enabled?
      return false unless business.trial?
      return false if business.trial_conversion_initiated?
      return true if business.billing_manager?(current_user) || business.owner?(current_user)
      false
    end
  end
end
