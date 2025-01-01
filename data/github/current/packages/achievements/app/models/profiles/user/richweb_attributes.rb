# typed: true
# frozen_string_literal: true

module Profiles
  module User
    class RichwebAttributes
      include GitHub::Memoizer
      include UsersHelper
      include UrlHelper
      include RichwebHelper

      def self.build(layout_data, open_achievement, visible_models)
        new(layout_data, open_achievement, visible_models).build
      end

      def initialize(layout_data, open_achievement, visible_models)
        @layout_data = layout_data
        @open_achievement = open_achievement
        @visible_models = visible_models
      end

      def build
        if wants_achievement?
          attributes_for_achievement_show
        else
          attributes_for_achievements_index
        end
      end

      private

      attr_reader :layout_data, :open_achievement, :visible_models

      delegate :achievable, to: :open_achievement, private: true

      def wants_achievement?
        open_achievement.present?
      end

      def render_text_with_substitutions(text)
        Achievable::SubstitutedText.new(
          text,
          achievement: open_achievement,
          current_user: layout_data.viewer,
          visible_models: visible_models,
        ).to_s
      end

      def attributes_for_achievement_show
        {
          title: user_achievements_title(
            login: layout_data.login_name,
            name: layout_data.profile_name,
          ),
          description: render_text_with_substitutions(open_achievement.description_template),
          updated_time: open_achievement.unlocked_at,
          image: achievable.social_card_asset_url(
            tier: open_achievement.tier,
            skin_tone_block: layout_data.method(:achievement_skin_tone),
          ),
          card: "summary",
        }
      end

      def attributes_for_achievements_index
        {
          title: "#{layout_data.login_name} - Achievements",
          url: user_url(layout_data.profile_user),
          image: "#{layout_data.primary_avatar_url}?s=400",
          username: layout_data.login_name,
          description: h(
            profile_page_meta_description(
              login: layout_data.login_name,
              profile_bio: layout_data.profile_bio,
              public_repo_count: layout_data.repository_count,
            ),
          ),
          type: "profile",
          card: "summary",
        }
      end
    end
  end
end
