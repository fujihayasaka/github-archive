# typed: true
# frozen_string_literal: true

class Issue::Loader::Timeline < Issue::Loader::Base
  include TimelineHelper

  attr_reader :pagination_params, :timeline_entries

  def initialize(context, pagination_params)
    @context = context
    @issue = context.issue
    @viewer = context.viewer
    @pagination_params = pagination_params

    @page_size =
      if pagination_params[:per_page]
        pagination_params[:per_page].to_i
      else
        DEFAULT_PAGE_SIZE / 2
      end

    @timeline_entries = load_timeline_entries
  end

  def total_count
    timeline_model.async_total_count.sync
  end

  def updated_at
    timeline_model.async_updated_at(fallback: pagination_params[:timeline_since]&.to_time&.utc).sync
  end

  def focused_item
    return @focused_item if defined?(@focused_item)
    return unless pagination_params[:focused_item_global_id]

    page = timeline_model.get_page(focus: pagination_params[:focused_item_global_id])
    @focused_item = page.async_page_count.sync > 0 ? page : nil
  end

  def previous_page_hidden_items_count
    return 0 unless focused_item
    return 0 if previous_page_after_cursor.nil? || previous_page_before_cursor.nil?

    timeline_model.async_count_between(
      before: previous_page_after_cursor,
      after: previous_page_before_cursor
    ).sync
  end

  def previous_page_after_cursor
    return unless focused_item
    @previous_page_after_cursor ||= pagination_params[:after_cursor]
  end

  def previous_page_before_cursor
    return unless focused_item
    @previous_page_before_cursor ||= focused_item.async_start_cursor.sync
  end

  def next_page_hidden_items_count
    return 0 unless timeline_model.async_total_count.sync > @page_size * 2
    return 0 unless next_page_before_cursor

    first_shown_cursor = timeline_start.async_end_cursor.sync
    return 0 unless first_shown_cursor

    timeline_model.async_count_between(before: first_shown_cursor, after: next_page_before_cursor).sync
  end

  def next_page_after_cursor
    @next_page_after_cursor ||= focused_item ? focused_item.async_start_cursor.sync : timeline_start.async_end_cursor.sync
  end

  def next_page_before_cursor
    @next_page_before_cursor ||= pagination_params[:before_cursor] || timeline_end.async_start_cursor.sync
  end

  sig { returns(Issues::Timeline::TimelinePage) }
  def timeline_start
    return focused_item if focused_item

    @timeline_start ||= timeline_model.get_page(
      first: @page_size,
      after_cursor: pagination_params[:after_cursor],
      before_cursor: pagination_params[:before_cursor]
    )
  end

  sig { returns(Issues::Timeline::TimelinePage) }
  def timeline_end
    # we only do the split pagination on the initial render, when loading additional items we load them all in timeline_start_placeholders
    return empty_page if loading_additional_items?

    @timeline_end ||= if timeline_model.async_total_count.sync <= @page_size
      empty_page
    else
      timeline_model.get_page(
        skip: @page_size,
        last: @page_size,
        after_cursor: pagination_params[:after_cursor],
        before_cursor: pagination_params[:before_cursor]
      )
    end
  end

  sig { returns(Issues::Timeline::Timeline) }
  def timeline_model
    raise NotImplementedError, "Must be implemented by subclass"
  end

  protected

  def loading_additional_items?
    pagination_params[:after_cursor].present?
  end

  sig { returns(Issues::Timeline::TimelinePage) }
  def empty_page
    timeline_model.get_page(first: 0)
  end

  def load_timeline_entries
    Platform::Security::RepositoryAccess.with_viewer(@viewer) do
      Promise.all(
        [timeline_start.async_entries, timeline_end.async_entries]
      ).then do |timeline_start_entries, timeline_end_entries|
        T.must(timeline_start_entries) + T.must(timeline_end_entries)
      end.sync
    end
  end
end
