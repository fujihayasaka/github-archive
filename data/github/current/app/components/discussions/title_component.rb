# typed: true
# frozen_string_literal: true

module Discussions
  class TitleComponent < ApplicationComponent
    extend T::Sig
    include ::TextHelper

    delegate(
      :bot_identifier,
      :current_repository_writable?,
      :discussions_search_path,
      :discussion_view_click_attrs,
      to: :helpers
    )

    # org_param - the display_login of the Organization to use in routing, if working with org-level discussions
    sig do
      params(
        discussion: T.untyped,
        timeline: T.untyped,
        parsed_discussions_query: T.untyped,
        org_param: T.nilable(String)
      ).void
    end
    def initialize(discussion:, timeline:, parsed_discussions_query:, org_param: nil)
      @discussion = discussion
      @timeline = timeline
      @parsed_discussions_query = parsed_discussions_query
      @org_param = org_param
    end

    private

    attr_reader :discussion, :timeline, :parsed_discussions_query

    sig { returns T.nilable(String) }
    attr_reader :org_param

    delegate :repository, to: :timeline

    delegate :category, :chosen_comment, to: :discussion

    memoize def chosen_comment_author
      chosen_comment&.safe_user
    end

    def repo_or_org
      if repository.organization_discussion.present?
        timeline.repo_owner.name + " Organization Discussions"
      else
        repository.name_with_display_owner
      end
    end

    def safe_author_data_attrs
      safe_data_attributes(author_data_attrs)
    end

    def author_data_attrs
      helpers.discussion_view_click_attrs(
        discussion,
        target: :USER_PROFILE_LINK,
      ).merge(hovercard_data_attributes_for_user_login(discussion.author_display_login))
    end

    memoize def can_modify?
      timeline.can_update_discussion?
    end

    def category_emoji
      emoji_tag(emoji_for(category.emoji), class: "f5")
    end

    def show_pinned_indicator?
      timeline.pinned?
    end

    def show_locked_indicator?
      discussion.locked?
    end
  end
end
