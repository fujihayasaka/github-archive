# typed: true
# frozen_string_literal: true

module Discussions
  class ChildCommentsComponent < ApplicationComponent
    # timeline - a DiscussionTimeline
    # parent_comment - a DiscussionComment whose nested/child comments should be rendered
    def initialize(timeline:, parent_comment:, page: 1, back_page: 0, forward_page: 0, anchor_id: nil)
      @timeline = timeline
      @parent_comment = parent_comment
      @page = page
      @back_page = back_page
      @forward_page = forward_page
      @anchor_id = anchor_id
    end

    private

    attr_reader :timeline, :parent_comment, :page, :back_page, :forward_page

    delegate :discussion_number, :repo_name, :repo_owner_login, to: :timeline

    def render?
      parent_comment.present? && GitHub.discussions_available_on_platform?
    end

    memoize def child_comments
      timeline.child_comments(parent_comment)
    end

    memoize def anchor_id
      @anchor_id || child_comments.first&.id
    end

    def total_visible_child_comments_count
      timeline.total_visible_child_comments_count(parent_comment)
    end

    memoize def total_previous_child_comments_count
      timeline.total_previous_child_comments_count(parent_comment)
    end

    memoize def total_next_child_comments_count
      timeline.total_next_child_comments_count(parent_comment)
    end

    def show_previous_replies_text
      units = pluralize(total_previous_child_comments_count, "previous reply")
      "Show #{units}"
    end

    def show_more_replies_text
      units = pluralize(total_next_child_comments_count, "more reply")
      "Show #{units}"
    end

    # Private: Get a linked avatar to represent the author of the given discussion or comment.
    #
    # discussion_or_comment - a Discussion or DiscussionComment instance
    #
    # Returns HTML.
    def discussion_timeline_avatar(discussion_or_comment)
      is_nested = discussion_or_comment.nested?
      is_via_app = discussion_or_comment.performed_via_integration

      content_tag(:div, class: class_names(
        "avatar-parent-child flex-column flex-items-center",
        "mr-2" => !is_nested && is_via_app,
        "TimelineItem-avatar left-0" => is_nested,
        "ml-3" => is_nested && !is_via_app,
        "ml-2" => is_nested && is_via_app,
      )) do
        safe_join([
          discussion_or_comment_author_avatar_link(discussion_or_comment, is_nested: is_nested),
          discussion_app_or_bot_author_label(discussion_or_comment),
        ].compact)
      end
    end

    def discussion_or_comment_author_avatar_link(discussion_or_comment, is_nested:)
      helpers.linked_avatar_for(
        discussion_or_comment.author,
        30,
        img_class: "avatar rounded-2 mr-2",
        link_data: helpers.discussion_view_click_attrs(discussion_or_comment, target: :USER_PROFILE_LINK),
      )
    end

    def discussion_app_or_bot_author_label(discussion_or_comment)
      if discussion_or_comment.performed_via_integration
        discussion_app_logo_link(discussion_or_comment.performed_via_integration)
      end
    end

    def discussion_app_logo_link(app)
      link_to(
        image_tag(app.preferred_avatar_url(size: 40),
          alt: "#{app.name}",
          width: 20, height: 20,
          class: "avatar avatar-child rounded-2"),
        app.url,
      )
    end
  end
end
