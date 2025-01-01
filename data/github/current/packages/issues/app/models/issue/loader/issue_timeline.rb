# typed: true
# frozen_string_literal: true

class Issue::Loader::IssueTimeline < Issue::Loader::Timeline
  extend T::Sig

  def initialize(context, pagination_params)
    super(context, pagination_params)

    # The page size should not be able to be over 60
    @page_size = [@page_size, DEFAULT_PAGE_SIZE].min
  end

  def self.load_for(context, pagination_params)
    super new(context, pagination_params)
  end

  sig { returns(Issues::Timeline::IssueTimeline) }
  def timeline_model
    return @timeline_model if defined?(@timeline_model)

    # Based on: app/platform/resolvers/timeline_items.rb
    # Merge queue and auto-merge events are internal, so we need to exclude them from external requests
    exclude_item_types = [Platform::Objects::AddedToMergeQueueEvent.graphql_name, Platform::Objects::RemovedFromMergeQueueEvent.graphql_name]

    filter_options = {
      exclude_item_types: exclude_item_types,
      item_types: Platform::Unions::PullRequestTimelineItems.possible_types,
      visible_events_only: true,
      filter_closed_if_preceded_by_merged: false,
      cap_filter: @context.cap_filter,
      since: pagination_params[:timeline_since],
      show_project_events: true,
    }

    @timeline_model = Issues::Timeline::IssueTimeline.for(@issue, @viewer, filter_options)
  end
end
