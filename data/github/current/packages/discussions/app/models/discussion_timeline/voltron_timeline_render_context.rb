# typed: true
# frozen_string_literal: true

# Public: Represents a single discussions page in a repository with "hidden items"
# which are comments and events we haven't loaded yet. "hidden items" are not
# minimized comments, but may contain minimized comments.
class DiscussionTimeline::VoltronTimelineRenderContext
  include DiscussionTimeline::RenderContext
  include GitHub::Memoizer

  # Public: Access the number of timeline items that should be rendered before hiding
  # any that remain.
  sig { returns(T.untyped) }
  def self.items_per_page
    DiscussionTimeline::PaginatedRenderContext.items_per_page
  end

  # Public: Set the number of timeline items that should be rendered before
  # hiding occurs.
  #
  # count - a positive integer
  sig { params(count: T.untyped).returns(T.untyped) }
  def self.items_per_page=(count)
    DiscussionTimeline::PaginatedRenderContext.items_per_page = count
  end

  sig do
    params(
      discussion: T.untyped,
      viewer: T.untyped,
      before_cursor: T.untyped,
      after_cursor: T.untyped,
      items_per_page: T.untyped,
      sort: T.untyped,
      cap_filter: T.untyped,
      first_half: T.untyped
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
    first_half: true
  )
    @discussion = discussion
    @viewer = viewer
    @before_cursor = before_cursor
    @after_cursor = after_cursor
    @items_per_page = items_per_page || self.class.items_per_page
    @sort = sort
    @cap_filter = cap_filter
    @first_half = first_half

    @paginated_render_context = DiscussionTimeline::PaginatedRenderContext.new(
      discussion,
      viewer: viewer,
      before_cursor: before_cursor,
      after_cursor: after_cursor,
      items_per_page: @items_per_page,
      sort: sort,
      cap_filter: cap_filter,
      include_events: @include_events
    )
  end

  # RenderContext module overrides

  attr_reader :cap_filter, :discussion, :viewer, :sort, :items_per_page, :first_half

  sig { returns(T.untyped) }
  def reply_threads_by_parent_id
    @paginated_render_context.reply_threads_by_parent_id
  end

  # Public: Returns an array of items to render on the discussions page.
  #
  # Each element in the returned array will be one of:
  # * Array - an array composed of DiscussionComments
  # * Symbol - :unread_marker representing where to render the unread div,
  #   or :comment_count representing the label that says how many comments there are,
  #   or :new_marker representing where to render the "what's new" div.
  # * DiscussionHiddenItems - Representation of items we aren't showing to the
  #   user and allow to load async
  #
  # Returns an array of the above elements
  sig { returns(T.untyped) }
  memoize def renderables
    paginated_render_context_renderables = @paginated_render_context.renderables

    # flatten renderables, break into 2 halves
    group_1, group_2, group3 = paginated_render_context_renderables.flatten.in_groups(3, false)
    #This will render more comments in the last half
    current_group = first_half ? group_1 : group_2 + group3

    # chunk back into arrays of comments
    current_group.chunk_while { |i, j| j.is_a?(DiscussionComment) && i.is_a?(DiscussionComment) }.map do |chunk|
      first = chunk[0]
      first.is_a?(DiscussionComment) ? chunk : first
    end
  end

  sig { returns(T.untyped) }
  memoize def timeline_items
    renderables.flatten.filter { |item| item.is_a?(DiscussionComment) }
  end

  sig { returns(T.untyped) }
  memoize def new_item_count
    @paginated_render_context.new_item_count
  end

  sig { returns(T.untyped) }
  def max_number_of_nested_comments
    DiscussionTimeline::DEFAULT_INITIAL_REPLY_COUNT
  end

  sig { returns(T::Boolean) }
  def render_reaction_placeholders?
    true
  end

  sig { returns(T::Boolean) }
  def render_discussion?
    first_half
  end

  sig { returns(T::Boolean) }
  def render_with_voltron?
    true
  end

  sig { override.returns(T::Boolean) }
  def will_render_new_marker?
    renderables.any? { |renderable| renderable == new_marker }
  end

  sig { returns(T.untyped) }
  def new_marker
    DiscussionTimeline::NEW_MARKER
  end

  private

  def include_events?
    false
  end

  def paginate_events?
    false
  end
end
