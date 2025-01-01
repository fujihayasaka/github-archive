# typed: true
# frozen_string_literal: true

module Conduit
  class ProfileFeedVisibilityComponent < ApplicationComponent
    def initialize(setting: nil, user:)
      @user = user
      @setting = setting
    end

    def render?
      logged_in? && @user == current_user
    end

    private

    def setting
      if @setting.nil?
        @setting = current_user.settings.get(:user_profile_feed_visible)
      end
      @setting
    end

    memoize def update_url
      profile_feed_visibility_setting_path(user_id: current_user.display_login)
    end
  end
end
