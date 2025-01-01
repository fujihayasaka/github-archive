# typed: true
# frozen_string_literal: true

module Discussions
  class HeaderComponent < ApplicationComponent
    # discussion_or_comment - a Discussion or DiscussionComment
    # timeline - a DiscussionTimeline
    def initialize(discussion_or_comment:, timeline:)
      @discussion_or_comment = discussion_or_comment
      @timeline = timeline
    end

    private

    attr_reader :discussion_or_comment, :timeline

    delegate :author, to: :discussion_or_comment

    def render?
      discussion_or_comment.present? && timeline.present?
    end

    def href
      "##{discussion_or_comment.dom_id}"
    end

    def viewer_can_react?
      logged_in?
    end

    memoize def nested_comment?
      discussion_or_comment.nested?
    end

    def click_profile_hydro_data
      helpers.discussion_view_click_attrs(discussion_or_comment, target: :USER_PROFILE_LINK)
    end

    def heading_tag
      if discussion_or_comment.is_a?(Discussion)
        :h2
      else
        nested_comment? ? :h4 : :h3
      end
    end

    def show_abuse_report_tooltip?
      logged_in? && current_user.site_admin? && report_count > 0
    end

    memoize def report_count
      timeline.report_count_for(discussion_or_comment)
    end

    memoize def can_view_original_author?
      return true unless helpers.posted_as_admin?(discussion_or_comment)

      helpers.can_view_original_author?(discussion_or_comment)
    end

    memoize def author_display_text
      return author.display_login unless helpers.posted_as_admin?(discussion_or_comment)

      "Admin #{author.display_login}"
    end

    def show_discussion_or_comment_edit_history?
      if discussion_or_comment.is_a?(DiscussionComment)
        !discussion_or_comment.wiped? || helpers.site_admin?
      else
        # Expect this helper to only be called from the discussion page,
        # and if you're there, you have read access to the repository,
        # which means you should be able to view the edit history
        # on the original post of the discussion.
        true
      end
    end
  end
end
