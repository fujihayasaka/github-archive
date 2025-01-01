# typed: true
# frozen_string_literal: true

module Site::CustomerStories
  class BaseController < Site::BaseController
    stylesheet_bundle "customer-stories"

    private

    def marketing_turbo_enable
      @marketing_turbo_disabled = false
    end

    def customer_stories_staff?
      return false unless FeatureFlag.vexi.enabled_or_raise?(:contentful_customer_stories, current_user) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
      return false unless logged_in?

      current_user&.employee?
    end
  end
end
