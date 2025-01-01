# typed: true
# frozen_string_literal: true

# Public: Represents a permalinked comment in a single discussions show view
# e.g., `discussioncomment-1` in "http://github.localhost/user/repo/discussions/1#discussioncomment-1"
class DiscussionTimeline::PermalinkRenderContext
  include DiscussionTimeline::RenderContext
  include GitHub::Memoizer

  CONTEXT_BEFORE = 3

  attr_reader :discussion, :viewer, :cap_filter

  sig do
    params(
      discussion: T.untyped,
      viewer: T.untyped,
      before_cursor: T.untyped,
      after_cursor: T.untyped,
      permalink_comment: T.untyped,
      anchor_id: T.untyped,
      cap_filter: T.untyped
    ).void
  end
  def initialize(discussion,
    viewer:,
    before_cursor:,
    after_cursor:,
    permalink_comment:,
    anchor_id:,
    cap_filter:
  )
    @discussion = discussion
    @viewer = viewer
    @cap_filter = cap_filter
    @before_cursor = before_cursor
    @after_cursor = after_cursor
    @anchor_id = anchor_id
    @permalink_comment = permalink_comment
  end

  # RenderContext module overrides

  sig { returns(T.untyped) }
  memoize def reply_threads_by_parent_id
    threads = DiscussionComment::ReplyThread.all_from_discussion(discussion, viewer: viewer,
      last_read_at: last_read_at)
    if permalink_comment.present?
      threads[permalink_comment.id] = permalink_comment.reply_thread(
        viewer: viewer,
        anchor_id: anchor_id,
        older: CONTEXT_BEFORE,
      )
    end

    threads
  end

  sig { returns(T.untyped) }
  def renderables
    if permalink_comment.present?
      [
        hidden_items_before_permalink_comment,
        [permalink_comment],
        hidden_items_after_permalink_comment,
      ]
    else
      [
        DiscussionTimelineHiddenItems.new(
          all_timeline_items.count,
          before: before_cursor,
          after: after_cursor,
        )
      ]
    end
  end

  sig { returns(T.untyped) }
  def timeline_items
    if permalink_comment.present?
      [permalink_comment]
    else
      []
    end
  end

  sig { returns(T::Boolean) }
  def render_reaction_placeholders?
    true
  end

  sig { returns(T::Boolean) }
  def render_discussion?
    false
  end

  sig { params(item: T.untyped).returns(T::Boolean) }
  def item_between_cursors?(item)
    all_timeline_items.any? do |timeline_item|
      item == timeline_item
    end
  end

  sig { override.returns(T::Boolean) }
  def will_render_new_marker?
    false
  end

  private

  attr_reader :before_cursor, :after_cursor, :permalink_comment, :anchor_id

  memoize def permalink_comment_index
    all_timeline_items.index(permalink_comment)
  end

  def hidden_items_before_permalink_comment
    DiscussionTimelineHiddenItems.new(
      permalink_comment_index,
      before: permalink_comment,
      after: after_cursor,
    )
  end

  def hidden_items_after_permalink_comment
    after_cursor_count = [0, all_timeline_items.size - permalink_comment_index - 1].max

    DiscussionTimelineHiddenItems.new(
      after_cursor_count,
      before: before_cursor,
      after: permalink_comment,
    )
  end

  memoize def all_timeline_items
    timeline = DiscussionTimeline::ItemFinder
      .new(discussion, viewer: viewer, timeline_items: timeline_items_for_discussion)

    if before_cursor && after_cursor
      timeline.between_cursors(before: before_cursor, after: after_cursor)
    end

    timeline.to_a
  end
end
