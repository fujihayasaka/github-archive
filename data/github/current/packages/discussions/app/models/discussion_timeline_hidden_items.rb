# typed: true
# frozen_string_literal: true

# Public: Represents the "x Hidden Items - Load more" portion of the page.
# Accepts a count to display to the user as well as a before/after cursor for
# the url generated to fetch more records.
class DiscussionTimelineHiddenItems
  extend T::Sig

  attr_reader :count, :before_cursor, :after_cursor

  sig { params(record: T.untyped).returns(T.untyped) }
  def self.to_cursor(record)
    if record.respond_to?(:global_relay_id)
      record.global_relay_id
    elsif record.respond_to?(:events)
      record.events.first.global_relay_id
    else
      record.to_s
    end
  end

  # Public: Iniitializes a hidden items
  #
  # count - The number of hidden items to display to the user
  # before - The record or cursor to turn into a cursor and use for pagination
  # after - The record or cursor to turn into a cursor and use for pagination
  sig { params(count: T.untyped, before: T.untyped, after: T.untyped).void }
  def initialize(count, before:, after:)
    @count = count
    @before_cursor = self.class.to_cursor(before)
    @after_cursor = self.class.to_cursor(after)
  end

  sig { params(other: T.untyped).returns(T.untyped) }
  def ==(other)
    other.is_a?(self.class) &&
      count == other.count &&
      before_cursor == other.before_cursor &&
      after_cursor == other.after_cursor
  end
end
