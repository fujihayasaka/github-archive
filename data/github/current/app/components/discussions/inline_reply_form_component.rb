# typed: true
# frozen_string_literal: true

class Discussions::InlineReplyFormComponent < ApplicationComponent
  include EnterpriseManagedUsersHelper

  def initialize(parent_comment:, timeline:, anchor_id: nil, back_page: 0)
    @parent_comment = parent_comment
    @timeline = timeline
    @anchor_id = anchor_id
    @back_page = back_page
  end

  private

  delegate :author, to: :parent_comment

  attr_reader :parent_comment, :timeline, :anchor_id, :back_page

  def render?
    return false if emu_contribution_blocked?(timeline&.repository)
    parent_comment.present? && timeline.present? && timeline.can_reply_to_discussion_comment?(parent_comment)
  end

  def aria_label_write_reply
    "Write a reply: #{author}, #{timestamp}"
  end

  def timestamp
    format = aria_label_date(parent_comment.created_at)
    parent_comment.created_at.to_formatted_s(format)
  end
end
