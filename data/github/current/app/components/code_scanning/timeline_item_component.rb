# typed: true
# frozen_string_literal: true

class CodeScanning::TimelineItemComponent < ApplicationComponent
  include AvatarHelper
  include CodeScanningHelper

  renders_one :body, lambda { |**system_arguments|
    system_arguments[:tag] = :span
    Primer::BaseComponent.new(**system_arguments)
  }

  renders_one :badge, lambda { |icon:, background: :subtle, color: :default|
    @icon = icon
    @background = background
    @color = color
  }

  attr_reader :timeline_event, :workflow_run, :repository
  sig do
    params(
      timeline_event: CodeScanning::AlertTimelineEvent,
      has_more_than_one_category: T::Boolean,
      initial_tool_version: T.nilable(String),
      commit: T.nilable(Commit),
      workflow_run: T.nilable(Actions::WorkflowRun),
      repository: T.nilable(Repository),
    ).void
  end
  def initialize(timeline_event:, has_more_than_one_category:, initial_tool_version:, commit:, workflow_run:, repository: nil)
    @timeline_event = timeline_event
    @has_more_than_one_category = has_more_than_one_category
    @initial_tool_version = initial_tool_version
    @commit = commit
    @workflow_run = workflow_run
    @repository = repository
  end

  def before_render
    raise RuntimeError.new("Badge slot is required") unless badge?
  end

  def show_analysis_origin?
    return false if timeline_event&.category&.blank?
    return false unless @has_more_than_one_category

    %i[
      TIMELINE_EVENT_TYPE_ALERT_APPEARED_IN_BRANCH
      TIMELINE_EVENT_TYPE_ALERT_CREATED
      TIMELINE_EVENT_TYPE_ALERT_REAPPEARED
      TIMELINE_EVENT_TYPE_ALERT_CLOSED_BECAME_FIXED
    ].include? event_type
  end

  def show_timeline_commit?
    return false if event_type == :TIMELINE_EVENT_TYPE_ALERT_APPEARED_IN_BRANCH

    timeline_event.commit_oid.present?
  end

  def request_id?
    timeline_event.request_id.present?
  end

  def request_id
    timeline_event.request_id
  end

  def event_ref
    timeline_event.ref_name_bytes
  end

  def show_path?
    return false if timeline_event.file_path.blank?
    return false if timeline_event.ref_name_bytes.blank?

    %i[TIMELINE_EVENT_TYPE_ALERT_CREATED TIMELINE_EVENT_TYPE_ALERT_REAPPEARED].include? event_type
  end

  def timestamp
    timeline_event.timestamp
  end

  def tool_version
    timeline_event.tool_version.presence
  end

  def tool_version_prefix
    return unless tool_version

    @initial_tool_version == tool_version ? "Tool version" : "Tool upgraded to"
  end

  def event_type
    timeline_event.type
  end

  def commit_exists?
    @commit.present?
  end

  def formatted_ref_name
    render Primer::Beta::Text.new(font_weight: :bold, classes: "branch-name") do
      display_ref_name(timeline_event.ref_name_bytes)
    end
  end

  def dismissal_request_reject_path
    urls.repository_code_scanning_dismissal_request_reject_path(repository.owner, repository)
  end

  def dismissal_request_approve_path
    urls.repository_code_scanning_dismissal_request_approve_path(repository.owner, repository)
  end

  def show_resolution_note?
    timeline_event.resolution_note.present? && %i[TIMELINE_EVENT_TYPE_ALERT_CLOSED_BY_USER TIMELINE_EVENT_TYPE_ALERT_DISMISSAL_REQUESTED].include?(event_type)
  end
end
