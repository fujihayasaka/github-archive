# typed: true
# frozen_string_literal: true

module Profiles
  module User
    module Achievements
      class ShareComponent < Profiles::User::Achievements::BaseComponent
        COPY_SHARE_LINK_ARIA_LABEL = "Copy share link to the system clipboard"
        COPY_SHARE_LINK_MENU_ITEM_TEXT = "Copy share link"
        PREVIEW_ON_TWITTER_MENU_ITEM_TEXT = "Preview on Twitter"
        PREVIEW_ON_TWITTER_URL = "#{SocialAccounts::Twitter.share_url}?text=%{twitter_preview_text}"
        PREVIEW_ON_TWITTER_TEXT = "I unlocked %{display_name} on @github! %{share_url}"

        # achievement - the achievement to share
        def initialize(achievement:)
          @achievement = achievement
        end

        private

        attr_reader :achievement

        def render?
          achievement.user == current_user
        end

        def share_url
          user_achievement_url(current_user, achievement.achievable_slug)
        end

        def twitter_preview_url
          PREVIEW_ON_TWITTER_URL % { twitter_preview_text: twitter_preview_text }
        end

        def twitter_preview_text
          URI.encode_www_form_component(
            PREVIEW_ON_TWITTER_TEXT % {
              display_name: achievement.achievable.display_name,
              share_url: share_url,
            },
          )
        end
      end
    end
  end
end
