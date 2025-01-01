# typed: true
# frozen_string_literal: true

module Discussions
  class TitleMetadataComponent < ApplicationComponent
    delegate(
      :avatar_for,
      :bot_identifier,
      :current_repository,
      :discussion_view_click_attrs,
      :hydro_click_tracking_attributes,
      to: :helpers,
    )

    def initialize(discussion:, in_sticky_header: false, timeline:)
      @discussion = discussion
      @in_sticky_header = in_sticky_header
      @timeline = timeline
    end

    private

    attr_reader :discussion, :in_sticky_header, :timeline

    def comment_count
      "#{number_with_delimiter(discussion.direct_comment_count)} #{comment_label}"
    end

    memoize def reply_count
      discussion.comment_count - discussion.direct_comment_count
    end

    def formatted_reply_count
      "#{number_with_delimiter(reply_count)} #{"reply".pluralize(reply_count)}"
    end

    def comment_label
      label = "comment"
      label.pluralize(discussion.comment_count)
    end

    def safe_author_data_attrs
      safe_data_attributes(author_data_attrs)
    end

    def author_data_attrs
      data_attrs = helpers.discussion_view_click_attrs(
        discussion,
        target: :USER_PROFILE_LINK,
      ).merge(hovercard_data_attributes_for_user_login(discussion.author_display_login))

      if in_sticky_header?
        data_attrs.merge("hovercard-z-index-override" => "111")
      else
        data_attrs
      end
    end

    def in_sticky_header?
      in_sticky_header
    end
  end
end
