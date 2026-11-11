# typed: true
# frozen_string_literal: true

module Profiles
  module User
    module Achievements
      class ShowComponent < Profiles::User::Achievements::BaseComponent
        # profile_user - User whose profile you're looking at.
        # achievements - Non-empty Array<Achievement> with one item for each unlocked tier of this achievement,
        #  ordered by increasing tier.
        # visible_models - Set containing the subset of unlocking models associated with achievements that are
        #   permitted to be seen by authzd and CAP filters on the current request.
        # is_hovercard - Whether this is being rendered in a hovercard.
        def initialize(profile_user:, achievements:, visible_models:, is_hovercard: false)
          @profile_user = profile_user
          @visible_models = visible_models
          @achievements = achievements
          @is_hovercard = is_hovercard
        end

        private

        attr_reader :profile_user, :achievements, :visible_models

        def render?
          return false unless GitHub.achievements_enabled?
          return false unless achievements.any?

          achievable.enabled?(current_user)
        end

        def hovercard?
          @is_hovercard
        end

        def oldest_achievement
          achievements.first
        end

        def highest_tier_achievement
          achievements.last
        end
        alias_method :achievement, :highest_tier_achievement

        def achievable
          highest_tier_achievement.achievable
        end

        def fully_unlocked?
          highest_tier_achievement.tier == achievable.highest_tier
        end

        def unlocked_tier_names
          @_unlocked_tier_names ||= 1.upto(highest_tier_achievement.tier).map do |tier_ord|
            achievable.tier(tier_ord).name.capitalize
          end
        end

        def first_tier?
          highest_tier_achievement.tier == 0
        end

        def gradient_path
          achievable.gradient_asset_url
        end

        def skin_tone_block
          profile_user.profile_settings.method(:preferred_emoji_skin_tone)
        end

        def badge_asset_path(tier: 0)
          achievable.badge_asset_path(tier: tier, skin_tone_block: skin_tone_block)
        end

        def share_url
          user_achievement_url(profile_user, achievement.achievable_slug)
        end
      end
    end
  end
end
