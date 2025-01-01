# typed: true
# frozen_string_literal: true

class DiscussionTimeline::SidebarRenderContext
  extend T::Sig

  include DiscussionTimeline::RenderContext
  include GitHub::Memoizer

  sig do
    params(
      discussion: T.untyped,
      viewer: T.untyped,
      cap_filter: T.untyped,
      paginate_events: T.untyped
    ).void
  end
  def initialize(discussion, viewer:, cap_filter: nil, paginate_events: true)
    @discussion = discussion
    @viewer = viewer
    @cap_filter = cap_filter
    @paginate_events = paginate_events
  end

  # RenderContext module overrides

  attr_reader :cap_filter, :discussion, :viewer

  sig { returns(T.untyped) }
  memoize def events
    if paginate_events?
      events_without_pagination.first(DiscussionTimeline::PAGINATED_EVENTS_LIMIT)
    else
      events_without_pagination
    end
  end

  sig { returns(T.untyped) }
  def has_paginated_events?
    paginate_events? && events_without_pagination.size > DiscussionTimeline::PAGINATED_EVENTS_LIMIT
  end

  sig { override.returns(T.untyped) }
  def will_render_new_marker?
    false
  end

  private

  def paginate_events?
    @paginate_events
  end

  memoize def events_without_pagination
    discussion.unsorted_filtered_and_grouped_events_for(viewer).sort_by(&:created_at).reverse
  end
end
