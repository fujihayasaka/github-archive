# typed: strict
# frozen_string_literal: true

module Discussions
  class SpotlightComponent < ApplicationComponent
    extend T::Sig

    include AvatarHelper
    include BotHelper

    delegate :discussion, :discussion_author, to: :spotlight, private: true

    # org_param - the display_login of the Organization to use in routing, if working with org-level discussions
    sig do
      params(spotlight: DiscussionSpotlight, preview: T::Boolean, classes: String, org_param: T.nilable(String)).void
    end
    def initialize(spotlight:, preview: false, classes: "", org_param: nil)
      @spotlight = spotlight
      @preview = preview
      @classes = classes
      @org_param = org_param
    end

    private

    sig { returns(DiscussionSpotlight) }
    attr_reader :spotlight

    sig { returns(String) }
    attr_reader :classes

    sig { returns(T.nilable(String)) }
    attr_reader :org_param

    sig { returns(String) }
    def preview_path
      discussion_spotlight_preview_path(
        discussion.repository_owner_login,
        discussion.repository,
        discussion
      )
    end

    sig { returns(DiscussionCategory) }
    def category
      discussion.category
    end

    sig { returns(T.nilable(String)) }
    def category_emoji
      emoji_name = category.emoji
      emoji = emoji_for(emoji_name)

      if emoji
        emoji_tag(emoji, alias: emoji_name)
      end
    end

    sig { returns(T::Boolean) }
    def preview?
      @preview
    end

    sig { returns(T.nilable(String)) }
    def preview_style
      if spotlight.preconfigured_color
        color_stops = spotlight.color_stops
        # This is currently used by another helper and can't be extracted
        if color_stops
          helpers.discussion_spotlight_gradient_background_style(color_stops)
        end
      end
    end

    sig { returns(String) }
    def category_link
      agnostic_discussions_path(discussion.repository, org_param: org_param,
        discussions_q: "category:\"#{category.name}\"")
    end
  end
end
