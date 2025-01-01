# typed: false
# frozen_string_literal: true

module Platform
  module Helpers
    module AchievementAvailability
      def async_should_return_achievements?
        return Promise.resolve(false) unless GitHub.achievements_enabled?
        return Promise.resolve(false) unless object.is_a?(User)
        object.profile_settings.async_achievements_enabled?
      end
    end
  end
end
