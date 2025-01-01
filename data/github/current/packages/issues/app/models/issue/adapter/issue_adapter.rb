# typed: true
# frozen_string_literal: true

class Issue::Adapter::IssueAdapter < Issue::Adapter::BaseCommentAdapter
  TYPES = ([
    PlatformTypes::Issue,
  ] + Issue::Adapter::BaseCommentAdapter::TYPES).freeze

  # object/issues
  attr_reader :database_id
  attr_reader :id
  attr_reader :number
  attr_reader :state_websocket
  attr_reader :task_list_item_count
  attr_reader :timeline
  attr_reader :timeline_end
  attr_reader :timeline_start
  attr_reader :timeline_websocket
  attr_reader :websocket
  attr_reader :resource_path
  attr_reader :issue

  # interfaces/comment
  attr_reader :authored_by_subject_author
  attr_reader :stafftools_url
  attr_reader :subject_id
  attr_reader :subject_type

  delegate :async_viewer_can_read_user_content_edits?, :async_latest_user_content_edit,
    :user, :async_user, :user_id, :global_relay_id, :created_at, :async_user_is_spammy,
    to: :@issue

  def created_via_email?
    # not applicable to issues
    false
  end
  alias :created_via_email :created_via_email?

  def initialize(
      context,
      timeline_loader: nil,
      skip_timeline: false,
      timeline_since: nil)
    issue = context.issue
    viewer = context.viewer

    super(context, object: issue)

    if TasklistBlocks::UrlExpander.enabled?(issue)
      @body = TasklistBlocks::UrlExpander.expand(issue)
    end

    @author = issue.user
    @authored_by_subject_author = false # not applicable to issues
    @database_id = issue.id
    @id = issue.global_relay_id
    @is_transfer_in_progress = issue.is_transfer_in_progress?
    @issue = issue
    @number = issue.number
    @owner = issue.owner
    @stafftools_url = nil # not applicable to issues
    @state_websocket = GitHub::WebSocket::Channels.issue_state(issue)
    @subject_id = nil
    @subject_type = nil # not applicable to issues
    @task_list_item_count = issue.lightweight_task_list_item_count
    @timeline_websocket = GitHub::WebSocket::Channels.issue_timeline(issue)
    @websocket = GitHub::WebSocket::Channels.issue(issue)
    @resource_path = resource_path_for(issue.path_uri)

    return if skip_timeline

    @timeline = Issue::Adapter::TimelineAdapter.new(context,
      timeline_loader: timeline_loader,
      timeline_since: timeline_since)

    @timeline_start = Issue::Adapter::TimelinePageAdapter.new(context,
      issue_adapter: self,
      timeline: timeline_loader&.timeline_model,
      timeline_page: timeline_loader&.timeline_start)

    @timeline_end = Issue::Adapter::TimelinePageAdapter.new(context,
      issue_adapter: self,
      timeline: timeline_loader&.timeline_model,
      timeline_page: timeline_loader&.timeline_end)
  end

  def viewer_can_comment?
    @viewer_can_comment
  end

  def is_transfer_in_progress?
    @is_transfer_in_progress
  end

  def new_record?
    @id.nil?
  end

  def has_tracking_blocks?
    @body&.include?("```[tasklist]")
  end

  sig { override.returns(T.nilable(T::Array[T::Class[T.anything]])) }
  def self.defined_types
    TYPES
  end
end
