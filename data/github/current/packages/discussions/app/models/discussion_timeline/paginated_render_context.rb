# typed: true
# frozen_string_literal: true

# Public: Represents a single discussions page in a repository with "hidden items"
# which are comments and events we haven't loaded yet. "hidden items" are not
# minimized comments, but may contain minimized comments.
class DiscussionTimeline::PaginatedRenderContext
  include DiscussionTimeline::RenderContext
  include GitHub::Memoizer

  # How many replies to load before a threaded answer
  CONTEXT_BEFORE = 3

  # Public: Access the number of timeline items that should be rendered before hiding
  # any that remain.
  sig { returns Integer }
  def self.items_per_page
    Discussions::Kv.store.get(DiscussionTimeline::ITEMS_PER_PAGE_KEY)
      .then { |value| GitHub::Result.new { Integer(value) } }
      .value { DiscussionTimeline::DEFAULT_ITEMS_PER_PAGE }
  end

  # Public: Set the number of timeline items that should be rendered before
  # hiding occurs.
  #
  # count - a positive integer
  sig { params(count: Integer).void }
  def self.items_per_page=(count)
    Discussions::Kv.store.set(DiscussionTimeline::ITEMS_PER_PAGE_KEY, count.to_s)
  end

  sig do
    params(
      discussion: Discussion,
      viewer: T.nilable(User),
      before_cursor: T.nilable(String),
      after_cursor: T.nilable(String),
      items_per_page: T.nilable(Integer),
      sort: T.nilable(String),
      cap_filter: T.nilable(ConditionalAccess::Web::Filter),
      include_events: T.nilable(T::Boolean),
      paginate_events: T::Boolean,
      show_stats: T.nilable(T.any(Discussions::NullShowStats, DiscussionsController::ShowStats))
    ).void
  end
  def initialize(
    discussion,
    viewer:,
    before_cursor: nil,
    after_cursor: nil,
    items_per_page: nil,
    sort: nil,
    cap_filter: nil,
    include_events: true,
    paginate_events: true,
    show_stats: nil
  )
    @discussion = discussion
    @viewer = viewer
    @before_cursor = before_cursor
    @after_cursor = after_cursor
    @items_per_page = items_per_page || self.class.items_per_page
    @sort = sort
    @cap_filter = cap_filter
    @include_events = !!include_events
    @paginate_events = paginate_events
    @show_stats = show_stats
  end

  # RenderContext module overrides

  sig { override.returns(T.nilable(ConditionalAccess::Web::Filter)) }
  attr_reader :cap_filter

  sig { override.returns(Discussion) }
  attr_reader :discussion

  sig { override.returns(T.nilable(User)) }
  attr_reader :viewer

  sig { returns T.nilable(String) }
  attr_reader :sort

  sig { returns Integer }
  attr_reader :items_per_page

  sig { returns T.any(Discussions::NullShowStats, DiscussionsController::ShowStats) }
  def show_stats
    @show_stats || super
  end

  sig { returns(T.untyped) }
  memoize def reply_threads_by_parent_id
    threads = DiscussionComment::ReplyThread.all_from_discussion(
      discussion,
      viewer: viewer,
      items_per_page: items_per_page,
      last_read_at: last_read_at,
    )
    parent_comment_of_answer = discussion.chosen_comment&.parent_comment
    if parent_comment_of_answer
      threads[parent_comment_of_answer.id] = parent_comment_of_answer.reply_thread(
        viewer: viewer,
        anchor_id: discussion.chosen_comment_id,
        older: CONTEXT_BEFORE,
      )
    end

    threads
  end

  # Public: Returns an array of items to render on the discussions page.
  #
  # Each element in the returned array will be one of:
  # * Array - an array composed of DiscussionComment + DiscussionEventGroup + DiscussionEvent
  # * Symbol - :unread_marker representing where to render the unread div,
  #   or :comment_count representing the label that says how many comments there are,
  #   or :new_marker representing where to render the "what's new" div.
  # * DiscussionHiddenItems - Representation of items we aren't showing to the
  #   user and allow to load async
  #
  # Returns an array of the above elements
  sig { returns(T.untyped) }
  memoize def renderables
    record_time(:renderables) do
      [
        timeline_header,
        *renderable_items,
        unread_marker,
      ].compact
    end
  end

  sig { returns(T.untyped) }
  memoize def timeline_items
    record_time(:timeline_items) do
      start_items + end_items
    end
  end

  sig { returns(T.untyped) }
  memoize def events
    if paginate_events?
      events_without_pagination.first(DiscussionTimeline::PAGINATED_EVENTS_LIMIT)
    else
      events_without_pagination
    end
  end

  sig { returns T::Boolean }
  def has_paginated_events?
    paginate_events? && events_without_pagination.size > DiscussionTimeline::PAGINATED_EVENTS_LIMIT
  end

  sig { returns Integer }
  def new_item_count
    @new_item_count ||= 0
  end

  sig { returns Integer }
  def max_number_of_nested_comments
    DiscussionTimeline::DEFAULT_INITIAL_REPLY_COUNT
  end

  sig { returns T::Boolean }
  def render_reaction_placeholders?
    true
  end

  # Private utilities

  sig do
    returns(T.any(
      T::Array[T.nilable(T.any(DiscussionEvent, DiscussionEventGroup, DiscussionTimelineHiddenItems, Symbol, T::Array[T.any(DiscussionComment, DiscussionEvent, DiscussionEventGroup, DiscussionTimelineHiddenItems, Symbol)]))],
      T::Array[T.any(
        DiscussionTimelineHiddenItems,
        T::Array[T.any(DiscussionComment, DiscussionEvent, DiscussionEventGroup)],
        Symbol
      )]
    ))
  end
  def renderable_items
    items = T.let(
      [start_items, hidden_items, end_items].compact,
      T::Array[T.any(
        DiscussionTimelineHiddenItems,
        T::Array[T.any(DiscussionComment, DiscussionEvent, DiscussionEventGroup)],
        Symbol
      )]
    )
    return items if last_read_at.nil?

    items = T.let(
      items.flatten,
      T::Array[T.any(DiscussionComment, DiscussionEvent, DiscussionEventGroup, DiscussionTimelineHiddenItems, Symbol)]
    )
    last_comment_index = items.rindex { |item| item.is_a?(DiscussionComment) }
    new_marker_index = items.rindex do |item|
      item.is_a?(DiscussionComment) && item.created_at && T.must(item.created_at) <= last_read_at
    end

    if new_marker_index
      @new_item_count = 0
      (items[(new_marker_index + 1)..-1] || []).each do |item|
        if item.is_a?(DiscussionComment)
          @new_item_count += 1
        elsif item.is_a?(DiscussionTimelineHiddenItems)
          @new_item_count += item.count
        end
      end
    end

    if new_marker_index && last_comment_index && new_marker_index < last_comment_index
      items.insert(new_marker_index + 1, new_marker)
      @will_render_new_marker = true
    end
    items.chunk_while { |i, j| j.is_a?(DiscussionComment) && i.is_a?(DiscussionComment) }.map do |chunk|
      first = chunk[0]
      first.is_a?(DiscussionComment) ? chunk : first
    end
  end

  sig { returns T::Boolean }
  def render_discussion?
    true
  end

  sig { override.returns(T::Boolean) }
  def will_render_new_marker?
    !!@will_render_new_marker
  end

  sig do
    params(
      items: T::Array[T.any(DiscussionComment, DiscussionEvent, DiscussionEventGroup)],
      items_per_page: Integer
    ).returns(T::Array[T.any(DiscussionComment, DiscussionEvent, DiscussionEventGroup)])
  end
  def self.start_items_for(items:, items_per_page:)
    items.take(items_per_page / 2)
  end

  sig do
    params(
      items: T::Array[T.any(DiscussionComment, DiscussionEvent, DiscussionEventGroup)],
      items_per_page: Integer
    ).returns(T::Array[T.any(DiscussionComment, DiscussionEvent, DiscussionEventGroup)])
  end
  def self.end_items_for(items:, items_per_page:)
    start_items_count = self.start_items_for(items: items, items_per_page: items_per_page).size
    items.drop(start_items_count).last(items_per_page - start_items_count)
  end

  private

  sig { returns T::Boolean }
  def paginate_events?
    @paginate_events
  end

  memoize def events_without_pagination
    timeline_items_for_discussion
      .filter { |e| [DiscussionEvent, DiscussionEventGroup].include? e.class }
      .reverse
  end

  sig { returns T::Boolean }
  def include_events?
    @include_events
  end

  sig { returns T.nilable(Symbol) }
  def timeline_header
    if before_cursor.nil? && after_cursor.nil?
      DiscussionTimeline::TIMELINE_HEADER
    end
  end

  sig { returns T::Array[T.any(DiscussionComment, DiscussionEvent, DiscussionEventGroup)] }
  memoize def start_items
    DiscussionTimeline::PaginatedRenderContext.start_items_for(
      items: timeline_items_between_cursors,
      items_per_page: items_per_page
    )
  end

  sig { returns T::Array[T.any(DiscussionComment, DiscussionEvent, DiscussionEventGroup)] }
  memoize def end_items
    DiscussionTimeline::PaginatedRenderContext.end_items_for(
      items: timeline_items_between_cursors,
      items_per_page: items_per_page
    )
  end

  sig { returns T.nilable(DiscussionTimelineHiddenItems) }
  def hidden_items
    if hidden_items?
      DiscussionTimelineHiddenItems.new(
        hidden_items_count,
        before: end_items.first || start_items.last,
        after: start_items.last,
      )
    end
  end

  sig { returns Integer }
  memoize def hidden_items_count
    timeline_items_between_cursors.size - (start_items.size + end_items.size)
  end

  sig { returns T::Boolean }
  def hidden_items?
    hidden_items_count > 0
  end

  attr_reader :timeline, :before_cursor, :after_cursor

  sig { returns T::Array[T.any(DiscussionComment, DiscussionEvent, DiscussionEventGroup)] }
  memoize def timeline_items_between_cursors
    record_time(:timeline_items_between_cursors) do
      timeline_item_finder = DiscussionTimeline::ItemFinder
        .new(discussion, viewer: viewer, timeline_items: timeline_items_for_discussion).sort_by(sort)

      if before_cursor && after_cursor
        timeline_item_finder.between_cursors(before: before_cursor, after: after_cursor)
      end

      timeline_item_finder.to_a
    end
  end

  sig { returns T.nilable(Symbol) }
  def unread_marker
    DiscussionTimeline::UNREAD_MARKER if before_cursor.nil? && after_cursor.nil?
  end

  sig { returns Symbol }
  def new_marker
    DiscussionTimeline::NEW_MARKER
  end

  sig { params(method_name: T.any(String, Symbol), block: T.proc.returns(T.untyped)).returns(T.untyped) }
  def record_time(method_name, &block)
    start_time = GitHub::Dogstats.monotonic_time
    yield
  ensure
    elapsed = GitHub::Dogstats.duration(start_time)
    GitHub.dogstats.distribution("discussion_timeline.paginated_render_context.dist", elapsed,
      tags: ["method:#{method_name}"])
  end
end
