# typed: true
# frozen_string_literal: true

module Profiles
  module User
    module Achievements
      class CardComponent < Profiles::User::Achievements::BaseComponent
        def initialize(achievement:, skin_tone_block:, open:)
          @achievement = achievement
          @skin_tone_block = skin_tone_block
          @open = open
        end

        private

        attr_reader :achievement, :skin_tone_block

        def render?
          return false unless achievement.present?
          return false unless GitHub.achievements_enabled?
          return false unless achievement.achievable.enabled?(current_user)

          true
        end

        def mine?
          logged_in? && achievement.user == current_user
        end

        def open?
          @open
        end

        def new?
          mine? && achievement.unseen?
        end

        def detail_src
          user_achievement_detail_path(achievement.user, achievement.achievable_slug)
        end

        def badge_asset_path
          achievement.achievable.badge_asset_path(skin_tone_block: skin_tone_block)
        end
      end
    end
  end
end
