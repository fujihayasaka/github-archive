# typed: true
# frozen_string_literal: true

module Feed
  class GetStartedComponent < ApplicationComponent
    include DashboardAnalyticsHelper

    def render?
      logged_in?
    end

    def current_context
      current_user
    end

    private

    def discover_people?
      user_feature_enabled?(:feed_discover_people)
    end
  end
end
