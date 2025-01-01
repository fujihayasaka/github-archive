# typed: true
# frozen_string_literal: true

class Hovercard::Adapter::HovercardAdapter < Issue::Adapter::Base
  include GitHub::Memoizer

  attr_reader :state_reason
  attr_reader :state
  attr_reader :title
  attr_reader :created_at
  attr_reader :resource_path
  attr_reader :author
  attr_reader :duplicate_of

  attr_reader :comment
  attr_reader :labels

  # PR specific fields
  attr_reader :base_ref_name
  attr_reader :head_ref_name
  attr_reader :head_repository_owner
  attr_reader :head_user

  attr_reader :tracked_in_issues
  attr_reader :hovercard_contexts

  attr_reader :database_id
  attr_reader :number
  attr_reader :body
  attr_reader :repository

  def initialize(context)
    super(context)
    issue = context.issue
    @is_pr = issue.pull_request?
    @issue_or_pr = @is_pr ? context.pull_requests_by_id[issue.pull_request_id] : issue
    @database_id = @issue_or_pr.id
    @number = @issue_or_pr.number
    @body = @issue_or_pr.body
    comment = context.comments_by_id.values&.first
    @author = @issue_or_pr.user

    @comment = Hovercard::Adapter::CommentAdapter.new(context, comment: comment) unless comment.nil?
    @repository = Hovercard::Adapter::RepositoryAdapter.new(context, repository: context.repository)
    # this is check against Plattform types therefore it has to be upper case
    @state = issue.state.upcase
    @state_reason = issue.state_reason&.upcase

    if @is_pr
      @base_ref_name = @issue_or_pr.display_base_ref_name
      @head_ref_name = @issue_or_pr.display_head_ref_name
      @head_user = @issue_or_pr.async_head_user.sync
      @head_repository_owner = head_user
      @is_cross_repo = @issue_or_pr.cross_repo?
      @state = "MERGED" if @issue_or_pr.merged?
    else
      @tracked_in_issues = context.tracked_in_issues
      @duplicate_of = context.duplicate_of
    end

    @title = issue.title
    @created_at = issue.created_at
    @resource_path = resource_path_for(issue.path_uri)

    @labels = issue.labels.map do |label|
      Issue::Adapter::LabelAdapter.new(context, label: label)
    end

    @hovercard_contexts = context.hovercard_context_involvements
  end

  # Override the `Issue::Adapter::Base#is_pull_request?` as we check a different type in this adapter
  def is_pull_request?
    @is_pr
  end

  def is_cross_repository?
    @is_cross_repo
  end

  def short_body_html(limit: 88)
    if is_pull_request?
      @issue_or_pr.async_truncated_body_html(limit).sync
    else
      @issue_or_pr.async_truncated_body_html(limit,
        strip_block_elements: false,
        strip_heading_elements: true,
        keep_svg_elements: true,
        strip_formatted_elements: true,
        context: { disable_issues_graph: @context.disable_issues_graph }
      ).sync
    end
  end

  def is_draft?
    @is_pr ? @issue_or_pr.draft? : false
  end

  memoize def is_in_merge_queue?
    @is_pr && @issue_or_pr.in_merge_queue?
  end

  sig { override.returns(T.nilable(T::Array[T::Class[T.anything]])) }
  def self.defined_types
    []
  end
end
