# typed: true
# frozen_string_literal: true

class Issue::Adapter::TimelinePageInfoAdapter < Issue::Adapter::Base
  def initialize(context, timeline_page:)
    super(context)
    @timeline_page = timeline_page
  end

  def start_cursor
    return @start_cursor if defined?(@start_cursor)
    @start_cursor = @timeline_page&.async_start_cursor&.sync
  end

  def end_cursor
    return @end_cursor if defined?(@end_cursor)
    @end_cursor = @timeline_page&.async_end_cursor&.sync
  end

  sig { override.returns(T.nilable(T::Array[T::Class[T.anything]])) }
  def self.defined_types
    []
  end
end
