# typed: true
# frozen_string_literal: true

module Platform
  module Resolvers
    class UserAchievements < Resolvers::Base
      include Platform::Helpers::AchievementAvailability

      type Connections.define(Objects::Achievement), null: false

      argument :include_hidden, Boolean, required: false, default_value: false,
        description: "Include your own achievements that you have hidden."

      def resolve(include_hidden:, **arguments)
        async_should_return_achievements?.then do |should_return_achievements|
          next ArrayWrapper.new([]) unless should_return_achievements

          object.async_batch_visible_highest_tier_achievements.then do |achievements|
            next ArrayWrapper.new([]) if achievements.nil?

            should_include_hidden = include_hidden && context[:viewer] == object

            enabled_achievements = achievements.select do |achievement|
              next false unless achievement.achievable&.enabled?(context[:viewer])

              !achievement.hidden? || should_include_hidden
            end
            ArrayWrapper.new(enabled_achievements)
          end
        end
      end
    end
  end
end
