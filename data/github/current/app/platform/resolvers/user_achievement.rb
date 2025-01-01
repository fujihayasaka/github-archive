# typed: true
# frozen_string_literal: true

module Platform
  module Resolvers
    class UserAchievement < Resolvers::Base
      include Platform::Helpers::AchievementAvailability

      type Objects::Achievement, null: true

      argument :slug, String, required: true, description: "The slug of the achievement to return."
      argument :include_hidden, Boolean, required: false, default_value: false,
        description: "Include your own achievements that you have hidden."

      def resolve(slug:, include_hidden:, **arguments)
        async_should_return_achievements?.then do |should_return_achievements|
          next nil unless should_return_achievements

          achievable = ::Achievable.with_slug(slug)
          next nil unless achievable&.enabled?(context[:viewer])

          object.profile_settings.async_show_private_contribution_count?.then do |show_private|
            visibility = show_private ? :PRIVATE : :PUBLIC

            should_include_hidden = include_hidden && context[:viewer] == object

            ach = object.highest_tier_achievement_for(achievable, visibility: visibility, viewer: context[:viewer])
            next nil if ach&.hidden? && !should_include_hidden
            ach
          end
        end
      end
    end
  end
end
