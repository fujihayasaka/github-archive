# typed: true
# frozen_string_literal: true

class Issue::Adapter::ProjectEventAdapter < Issue::Adapter::IssueEventAdapter
  ADDED_TO_PROJECT = "AddedToProjectEvent"
  REMOVED_FROM_PROJECT = "RemovedFromProjectEvent"
  MOVED_IN_PROJECT = "MovedColumnsInProjectEvent"
  CONVERTED_NOTE_TO_ISSUE = "ConvertedNoteToIssueEvent"
  SUPPORTED_TYPES = [ADDED_TO_PROJECT, REMOVED_FROM_PROJECT, MOVED_IN_PROJECT, CONVERTED_NOTE_TO_ISSUE].freeze

  TYPES = [PlatformTypes::ProjectEvent]

  attr_reader :project
  attr_reader :project_card
  attr_reader :project_column_name
  attr_reader :previous_project_column_name

  def initialize(context, event_id:, event_name:)
    raise "Invalid event name" unless SUPPORTED_TYPES.include?(event_name)
    super(context, event_id: event_id, event_name: event_name)

    project = context.projects_by_id[@issue_event.subject_id]

    @project = Issue::Adapter::ProjectAdapter.new(context, project: project) if project

    if @event_name != REMOVED_FROM_PROJECT
      project_card = context.project_cards_by_id[@issue_event.card_id]
      @project_card = Issue::Adapter::ProjectCardAdapter.new(context, project: project, project_card: project_card) if project_card
    end

    @project_column_name = @issue_event.column_name
    @previous_project_column_name = @issue_event.previous_column_name
  end

  def was_automated?
    @issue_event.automated?
  end

  sig { override.returns(T.nilable(T::Array[T::Class[T.anything]])) }
  def self.defined_types
    TYPES
  end
end
