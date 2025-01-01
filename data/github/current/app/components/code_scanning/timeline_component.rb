# typed: true
# frozen_string_literal: true

class CodeScanning::TimelineComponent < ApplicationComponent
  include AvatarHelper
  include CodeScanningHelper

  sig do
    params(
      timeline_events: T::Array[CodeScanning::AlertTimelineEvent],
      commit_map: T::Hash[String, Commit],
      workflow_run_map: T.nilable(T::Hash[Integer, Actions::WorkflowRun]),
      selected_ref: T.nilable(String),
      repository: T.nilable(Repository)).void
  end
  def initialize(timeline_events:, commit_map:, workflow_run_map:, selected_ref:, repository: nil)
    @timeline_events = timeline_events
    @commit_map = commit_map
    @workflow_run_map = workflow_run_map
    @users_map = T.let(User.where(id: timeline_events.map(&:user_id).compact.uniq).index_by(&:id), T::Hash[Integer, User])
    @selected_ref = selected_ref
    @repository = repository

    # The ghost user is fetched here, so we do not load it for each row.
    @ghost_user = T.let(User.ghost, User)
  end

  private

  sig { params(timeline_event: CodeScanning::AlertTimelineEvent).returns(T.nilable(Commit)) }
  def commit_for_timeline_event(timeline_event)
    @commit_map[timeline_event.commit_oid] unless @commit_map.nil?
  end

  sig { params(user_id: Integer).returns(User) }
  def safe_user(user_id)
    @users_map[user_id] || @ghost_user
  end

  sig { returns(T.nilable(String)) }
  memoize def initial_tool_version
    created_event = @timeline_events.find { |event| event.type == :TIMELINE_EVENT_TYPE_ALERT_CREATED }
    created_event&.tool_version
  end

  sig { returns(T::Boolean) }
  memoize def has_more_than_one_category?
    category = T.let(nil, T.nilable(String))
    !@timeline_events.all? do |e|
      category = e.category if category.nil?
      category == e.category
    end
  end

  sig { params(timeline_event: CodeScanning::AlertTimelineEvent).returns(T.nilable(Actions::WorkflowRun)) }
  def workflow_run_for_timeline_event(timeline_event)
    @workflow_run_map[timeline_event.workflow_run_id] unless @workflow_run_map.nil?
  end

  def exemption_evaluation_icon(timeline_event)
    status = timeline_event.compute_status
    if status == "approved"
      return :"check"
    end

    if status == "rejected"
      return :"x"
    end

    ""
  end

  def dismissal_resolution_msg(timeline_event)
    status = timeline_event.compute_status
    if status == "approved"
      return "approved dismissal"
    end

    if status == "rejected"
      return "denied dismissal"
    end

    ""
  end
end
