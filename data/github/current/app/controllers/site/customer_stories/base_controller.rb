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
      return false unless feature_enabled_globally_or_for_current_user?(:contentful_customer_stories)
      return false unless logged_in?

      current_user&.employee?
    end
  end
end
