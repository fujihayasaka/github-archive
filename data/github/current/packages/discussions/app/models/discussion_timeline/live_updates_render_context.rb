# typed: true
# frozen_string_literal: true

# Public: Represents new comments, events, and event groups that need to be
# rendered on the page via ajax.
class DiscussionTimeline::LiveUpdatesRenderContext
  include DiscussionTimeline::RenderContext
  include GitHub::Memoizer

  sig do
    params(
      discussion: T.untyped,
      viewer: T.untyped,
      timeline_last_rendered: T.untyped,
      cap_filter: T.untyped,
      sort: T.untyped
    ).void
  end
  def initialize(discussion, viewer:, timeline_last_rendered:, cap_filter:, sort: nil)
    @discussion = discussion
    @viewer = viewer
    @timeline_last_rendered = timeline_last_rendered
    @sort = sort
    @cap_filter = cap_filter
  end

  # RenderContext module overrides

  attr_reader :cap_filter, :discussion, :viewer, :sort

  sig { returns(T.untyped) }
  memoize def reply_threads_by_parent_id
    DiscussionComment::ReplyThread.all_from_discussion(discussion, viewer: viewer, last_read_at: nil)
  end

  sig { returns(T.untyped) }
  memoize def renderables
    [
      :unread_marker,
      new_timeline_items,
    ]
  end

  sig { returns(T.untyped) }
  def timeline_items
    new_timeline_items
  end

  # Private utilities

  private

  attr_reader :timeline_last_rendered

  memoize def new_timeline_items
    DiscussionTimeline::ItemFinder
      .new(discussion, viewer: viewer, timeline_items: timeline_items_for_discussion)
      .since(timeline_last_rendered)
      .sort_by(sort)
      .to_a
  end

  def will_render_new_marker?
    false
  end
end
