# typed: true
# frozen_string_literal: true

# Public: Used to find and filter DiscussionComment,
# DiscussionEvent, and DiscussionEventGroup objects.
class DiscussionTimeline::ItemFinder
  extend T::Sig

  sig { returns T::Array[T.any(DiscussionComment, DiscussionEvent, DiscussionEventGroup)] }
  attr_reader :timeline_items

  SORT_OLD = "old"
  SORT_NEW = "new"
  SORT_TOP = "top"
  VALID_SORT_OPTIONS = [SORT_OLD, SORT_NEW, SORT_TOP].freeze

  sig do
    params(
      discussion: Discussion,
      viewer: T.nilable(User),
      timeline_items: T::Array[T.any(DiscussionComment, DiscussionEvent, DiscussionEventGroup)]
    ).void
  end
  def initialize(discussion, viewer:, timeline_items:)
    @discussion = discussion
    @viewer = viewer
    @timeline_items = timeline_items
  end

  sig { returns T::Array[T.any(DiscussionComment, DiscussionEvent, DiscussionEventGroup)] }
  def to_a
    timeline_items
  end

  sig { params(before: T.untyped, after: T.untyped).returns(T.untyped) }
  def between_cursors(before:, after:)
    before_index = timeline_items.index { |item| cursor_id_match?(item, cursor: before) }
    after_index = timeline_items.index { |item| cursor_id_match?(item, cursor: after) }
    if before_index && after_index
      @timeline_items = timeline_items[after_index + 1...before_index] || []
    elsif before_index
      @timeline_items = timeline_items.take(before_index)
    elsif after_index
      @timeline_items = timeline_items.drop(after_index + 1)
    end

    self
  end

  sig { params(time: T.untyped).returns(DiscussionTimeline::ItemFinder) }
  def since(time)
    return self unless time.is_a?(Time)

    @timeline_items.select! do |item|
      item.created_at && T.must(item.created_at) > time
    end

    self
  end

  sig { params(sort: T.untyped).returns(T.untyped) }
  def sort_by(sort)
    case sort
    when nil, DiscussionTimeline::ItemFinder::SORT_OLD
      @timeline_items.sort_by!(&:created_at)
    when DiscussionTimeline::ItemFinder::SORT_NEW
      now = Time.now
      @timeline_items.sort_by! do |item|
        item.created_at ? now - T.must(item.created_at) : now
      end
    when DiscussionTimeline::ItemFinder::SORT_TOP
      comments, events = @timeline_items.partition { |item| item.is_a?(DiscussionComment) }
      comments.sort_by! { |c| -T.cast(c, DiscussionComment).total_upvotes }
      @timeline_items = comments + events.sort_by { |e| e.created_at || Time.now }
    end

    self
  end

  private

  attr_reader :discussion

  def cursor_id_match?(record, cursor:)
    DiscussionTimelineHiddenItems.to_cursor(record) == cursor
  end
end
