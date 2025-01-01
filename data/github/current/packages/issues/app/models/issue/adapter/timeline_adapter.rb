# typed: true
# frozen_string_literal: true

class Issue::Adapter::TimelineAdapter < Issue::Adapter::Base
  attr_reader :total_count
  attr_reader :updated_at
  attr_reader :previous_page_after_cursor
  attr_reader :previous_page_before_cursor
  attr_reader :previous_page_hidden_items_count
  attr_reader :next_page_after_cursor
  attr_reader :next_page_before_cursor
  attr_reader :next_page_hidden_items_count
  attr_reader :focused_item

  def initialize(context, timeline_loader:, timeline_since:)
    super(context)

    if timeline_loader.nil?
      @total_count = 0
      @updated_at = timeline_since&.to_time&.utc || context.issue.updated_at.to_time.utc
    else
      timeline = timeline_loader.timeline_model

      @total_count = timeline_loader.total_count
      @updated_at = timeline_loader.updated_at
      @previous_page_after_cursor = timeline_loader.previous_page_after_cursor
      @previous_page_before_cursor = timeline_loader.previous_page_before_cursor
      @previous_page_hidden_items_count = timeline_loader.previous_page_hidden_items_count
      @next_page_after_cursor = timeline_loader.next_page_after_cursor
      @next_page_before_cursor = timeline_loader.next_page_before_cursor
      @next_page_hidden_items_count = timeline_loader.next_page_hidden_items_count
      @focused_item = timeline_loader.focused_item
    end
  end

  sig { override.returns(T.nilable(T::Array[T::Class[T.anything]])) }
  def self.defined_types
    []
  end
end
