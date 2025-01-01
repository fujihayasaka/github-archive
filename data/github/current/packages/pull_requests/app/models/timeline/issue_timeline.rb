# typed: strict
# frozen_string_literal: true

class Timeline::IssueTimeline < Timeline::BaseTimeline
  include GitHub::Memoizer

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

  SUB_ISSUE_EVENT_TYPE_NAMES = %w(
    SubIssueAddedEvent
    SubIssueRemovedEvent
    ParentIssueAddedEvent
    ParentIssueRemovedEvent
  ).freeze

  PROJECTS_CLASSIC_EVENT_TYPE_NAMES = %w(
    AddedToProjectEvent
    RemovedFromProjectEvent
    MovedColumnsInProjectEvent
    ConvertedNoteToIssueEvent
  ).freeze

  # Internal: Compiles the unsorted list of timeline placeholders for issues.
  sig { override.returns(Promise[T::Array[Timeline::Placeholder::Base]]) }
  memoize def async_placeholders
    placeholders = T.let([], T::Array[Promise[T::Array[Timeline::Placeholder::Base]]])
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

    Promise.all(placeholders).then(&:flatten)
  end

  sig { returns(Promise[T::Array[Timeline::Placeholder::Base]]) }
  def async_issue_comment_placeholders
    Platform::Loaders::Timeline::Placeholders::IssueComment.load(subject.id, viewer)
  end

  sig { params(requested_issue_event_type_names: T::Array[String]).returns(Promise[T::Array[Timeline::Placeholder::Base]]) }
  def async_issue_event_placeholders(requested_issue_event_type_names: [])
    filtered_requested_issue_event_type_names = requested_issue_event_type_names

    unless filter_options[:show_project_events]
      filtered_requested_issue_event_type_names -= PROJECT_TIMELINE_EVENT_TYPE_NAMES
    end

    filtered_requested_issue_event_type_names -= PROJECTS_CLASSIC_EVENT_TYPE_NAMES

    if !SubIssuesFeature.enabled?(subject.repository)
      filtered_requested_issue_event_type_names -= SUB_ISSUE_EVENT_TYPE_NAMES
    end

    # If specific item types were originally requested, but after additional filtering there are no visible types
    # return early to ensure we don't process further and potentially return incorrect types.
    return Promise.all([]) if requested_issue_event_type_names.size > 0 && filtered_requested_issue_event_type_names.empty?
    Platform::Loaders::Timeline::Placeholders::IssueEvent.load(
      subject.id,
      subject.repository_id,
      viewer,
      visible_events_only: filter_options[:visible_events_only],
      requested_issue_event_type_names: filtered_requested_issue_event_type_names,
      cap_filter: filter_options[:cap_filter],
      total_count_optimization: filter_options[:total_count_optimization],
      first: filter_options[:first],
      total_count_limit: filter_options[:total_count_limit],
    )
  end

  sig { returns(Promise[T::Array[Timeline::Placeholder::Base]]) }
  def async_cross_reference_placeholders
    Platform::Loaders::Timeline::Placeholders::CrossReference.load(subject.id, viewer, cap_filter: filter_options[:cap_filter])
  end

  private

  sig { override.returns(Issue) }
  def subject
    super
  end

  sig { returns(T::Array[String]) }
  memoize def issue_event_type_names_for_issue
    Platform::Unions::IssueTimelineItems.possible_types.map(&:graphql_name)
  end

  # Filters out events that are not IssueEvent types
  # and events that are pull-request specific
  sig { returns(T::Array[String]) }
  memoize def requested_issue_event_type_names
    (requested_item_type_names - NON_ISSUE_EVENT_TYPE_NAMES) & issue_event_type_names_for_issue
  end
end
