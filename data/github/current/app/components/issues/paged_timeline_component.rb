# typed: true
# frozen_string_literal: true

module Issues
  class PagedTimelineComponent < ApplicationComponent
    include TimelineHelper

    attr_reader :timeline_owner, :render_focused_item_loader

    def initialize(timeline_owner:, render_focused_item_loader: false)
      @timeline_owner = timeline_owner
      @render_focused_item_loader = render_focused_item_loader
    end

    private

    delegate :previous_page_after_cursor, :previous_page_before_cursor, :previous_page_hidden_items_count,
             :next_page_after_cursor, :next_page_before_cursor, :next_page_hidden_items_count,
             :focused_item, to: :timeline

    def timeline
      timeline_owner.timeline
    end

    def has_previous_page
      previous_page_hidden_items_count&.positive?
    end

    def has_next_page
      next_page_hidden_items_count.positive?
    end

    memoize def start_nodes
      timeline_owner.timeline_start.nodes
    end

    memoize def end_nodes
      timeline_owner.timeline_end.nodes || []
    end

    def focused_item_path
      return nil unless render_focused_item_loader

      timeline_params = {
        id: timeline_owner.id,
        after_cursor: timeline_owner.timeline_start.page_info.end_cursor,
        before_cursor: timeline_owner.timeline_end.page_info.start_cursor,
        _features: params[:_features]
      }.compact

      "#{timeline_owner.repository.name_with_display_owner}/timeline_focused_item?#{timeline_params.to_param}"
    end
  end
end
