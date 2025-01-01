# typed: true
# frozen_string_literal: true

class Timeline::IssueTimeline < Timeline::BaseTimeline
  # Internal: List of Platform type names which are not backed by the `IssueEvent` model
  NON_ISSUE_EVENT_TYPE_NAMES = %w(
    IssueComment
    CrossReferencedEvent
  ).freeze

  PROJECT_TIMELINE_EVENT_TYPE_NAMES = %w(
    AddedToProjectV2Event
    RemovedFromProjectV2Event
    ProjectV2ItemStatusChangedEvent
    ConvertedFromDraftEvent
  ).freeze

  # Internal: Compiles the unsorted list of timeline placeholders for issues.
  def async_placeholders
    return @placeholders if defined?(@placeholders)

    placeholders = []
    if subject.has_timeline_items?
      if requested_item_type_names.include?("IssueComment")
        placeholders.push async_issue_comment_placeholders
      end

      if requested_item_type_names.include?("CrossReferencedEvent")
        placeholders.push async_cross_reference_placeholders
      end

      unless requested_issue_event_type_names.empty?
        placeholders.push async_issue_event_placeholders(requested_issue_event_type_names: requested_issue_event_type_names)
      end
    end

    @placeholders = Promise.all(placeholders).then(&:flatten)
  end

  def async_issue_comment_placeholders
    Platform::Loaders::Timeline::Placeholders::IssueComment.load(subject.id, viewer)
  end

  def async_issue_event_placeholders(requested_issue_event_type_names: [])
    unless filter_options[:show_project_events]
      requested_issue_event_type_names -= PROJECT_TIMELINE_EVENT_TYPE_NAMES
    end

    Platform::Loaders::Timeline::Placeholders::IssueEvent.load(
      subject.id,
      subject.repository_id,
      viewer,
      visible_events_only: filter_options[:visible_events_only],
      requested_issue_event_type_names: requested_issue_event_type_names,
      cap_filter: filter_options[:cap_filter]
    )
  end

  def async_cross_reference_placeholders
    Platform::Loaders::Timeline::Placeholders::CrossReference.load(subject.id, viewer, cap_filter: filter_options[:cap_filter])
  end

  private

  def issue_event_type_names_for_issue
    Platform::Unions::IssueTimelineItems.possible_types.map(&:graphql_name)
  end

  # Filters out events that are not IssueEvent types
  # and events that are pull-request specific
  def requested_issue_event_type_names
    (requested_item_type_names - NON_ISSUE_EVENT_TYPE_NAMES) & issue_event_type_names_for_issue
  end
end
