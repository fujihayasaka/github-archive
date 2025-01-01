# typed: true
# frozen_string_literal: true

class DiscussionTimeline::SingleCommentRenderContext
  extend T::Sig

  include DiscussionTimeline::RenderContext
  include GitHub::Memoizer

  sig do
    params(
      discussion: T.untyped,
      comment: T.untyped,
      viewer: T.untyped,
      cap_filter: T.untyped,
      nested_comments_page: T.untyped,
      nested_comments_per_page: T.untyped,
      anchor_id: T.untyped,
      back_page: T.untyped,
      forward_page: T.untyped
    ).void
  end
  def initialize(
    discussion,
    comment,
    viewer: nil,
    cap_filter: nil,
    nested_comments_page: nil,
    nested_comments_per_page: nil,
    anchor_id: 0,
    back_page: 0,
    forward_page: 0
  )
    @discussion = discussion
    @comment = comment
    @viewer = viewer
    @cap_filter = cap_filter
    @nested_comments_page = nested_comments_page
    @nested_comments_per_page = nested_comments_per_page
    @anchor_id = anchor_id
    @back_page = back_page
    @forward_page = forward_page
  end

  # RenderContext module overrides

  attr_reader :cap_filter, :discussion, :viewer

  sig { returns(T.untyped) }
  memoize def reply_threads_by_parent_id
    reply_thread = comment.reply_thread(
      viewer: viewer, anchor_id: @anchor_id, older: older_count, newer: newer_count)
    { comment.id => reply_thread }
  end

  sig { returns(T.untyped) }
  def renderables
    [[comment]]
  end

  sig { returns(T.untyped) }
  def timeline_items
    [comment]
  end

  sig { returns(T.untyped) }
  def max_number_of_nested_comments
    if nested_comments_paginated?
      nested_comments_per_page * nested_comments_page
    end
  end

  sig { override.returns(T.untyped) }
  def will_render_new_marker?
    false
  end

  # Private utilities

  private

  attr_reader :comment, :nested_comments_page, :nested_comments_per_page

  def nested_comments_paginated?
    nested_comments_page.present? && nested_comments_per_page.present?
  end

  def older_count
    return 0 unless nested_comments_per_page
    @back_page * nested_comments_per_page
  end

  def newer_count
    return 0 unless nested_comments_per_page
    @forward_page * nested_comments_per_page
  end
end
