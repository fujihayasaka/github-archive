# typed: true
# frozen_string_literal: true

class Discussions::DiscussionRowCollapsedComponent < ApplicationComponent
  include AvatarHelper
  include ::TextHelper
  include BotHelper

  def initialize(permissions: nil, discussion:, index:, participants:, parsed_discussions_query: [], header_element_name: :h3, org_param: nil)
    @permissions = permissions
    @discussion = discussion
    @index = index
    @participants = participants
    @parsed_discussions_query = parsed_discussions_query
    @header_element_name = header_element_name
    @org_param = org_param
  end

  private

  attr_reader :permissions, :discussion, :index, :participants, :parsed_discussions_query, :header_element_name, :org_param

  memoize def repo
    current_repository || discussion.repository
  end

  def participants_avatar_stack_class
    avatar_stack_count_class(participants.size)
  end

  def comments_aria_label
    format = aria_label_date(discussion.created_at)
    "#{pluralize(discussion.comment_count, "comment")}: #{discussion.author}, #{discussion.created_at.to_formatted_s(format)}"
  end

  memoize def discussion_has_answer?
    discussion.chosen_comment_id.present? && discussion.supports_mark_as_answer?
  end

  def discussion_type_text
    if discussion.supports_mark_as_answer?
      "asked"
    elsif discussion.supports_announcements?
      "announced"
    else
      "started"
    end
  end

  def comment_icon
    if discussion_has_answer?
      :"check-circle-fill"
    elsif discussion.supports_mark_as_answer?
      :"check-circle"
    else
      :comment
    end
  end

  def comment_icon_color
    if discussion_has_answer?
      :success
    else
      :muted
    end
  end
end
