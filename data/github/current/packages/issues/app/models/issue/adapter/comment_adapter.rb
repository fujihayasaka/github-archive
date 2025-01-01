# typed: true
# frozen_string_literal: true

class Issue::Adapter::CommentAdapter < Issue::Adapter::BaseCommentAdapter
  delegate :async_user, :async_viewer_can_read_user_content_edits?, :async_latest_user_content_edit,
    :created_at, :user_id, :global_relay_id, :async_user_is_spammy,
    to: :@object

  COMMENT_EVENT = "IssueComment"

  TYPES = ([
    PlatformTypes::IssueComment,
    PlatformTypes::Minimizable
  ] + Issue::Adapter::BaseCommentAdapter::TYPES).freeze

  MINIMIZE_REASONS = {
    ABUSE: "abuse",
    OFF_TOPIC:  "off-topic",
    OUTDATED: "outdated",
    RESOLVED: "resolved",
    DUPLICATE: "duplicate",
    SPAM: "spam",
  }.freeze

  # object/comments
  attr_reader :database_id
  attr_reader :id
  attr_reader :pull_request
  attr_reader :issue
  attr_reader :input_name
  attr_reader :url

  # interfaces/comment
  attr_reader :authored_by_subject_author
  attr_reader :subject_id
  attr_reader :subject_type

  # Minimizable
  attr_reader :is_minimized
  attr_reader :viewer_can_minimize
  attr_reader :minimized_reason

  # Sponsors
  attr_reader :author_to_repo_owner_sponsorship

  delegate :user, to: :@object

  def self.new(context, comment_id:, issue_adapter:)
    return nil unless context.comments_by_id[comment_id]
    super
  end

  def initialize(context, comment_id:, issue_adapter:)
    super(context, object: context.comments_by_id[comment_id])
    issue = context.issue
    viewer = context.viewer

    @author = @object.user
    @authored_by_subject_author = issue.user_id == @object.user_id
    @database_id = comment_id
    @id = @object.global_relay_id
    @input_name = "issue_comment"
    @is_minimized = @object.minimized?
    @issue = issue_adapter
    @minimized_reason = MINIMIZE_REASONS[@object.minimized_reason&.to_sym]

    @pull_request = Issue::Adapter::PullRequestAdapter.new(context, pull_request: issue.pull_request) if issue.pull_request

    @subject_id = issue.global_relay_id
    @subject_type = issue.pull_request? ? "pull request" : "issue"
    @viewer_can_minimize = @object.viewer_can_minimize?(viewer)
    @viewer_can_repo_push = @object.repository.pushable_by?(viewer)
    @url = @object.url

    if GitHub.sponsors_enabled? && context.author_to_repo_owner_sponsorships_by_author_id.present?
      @author_to_repo_owner_sponsorship = context.author_to_repo_owner_sponsorships_by_author_id[@object.user_id]
    end
  end

  def viewer_can_minimize?
    @viewer_can_minimize
  end

  def is_minimized?
    @is_minimized
  end
  alias :minimized? :is_minimized?

  def created_via_email?
    @object.created_via_email
  end
  alias :created_via_email :created_via_email?

  def stafftools_url
    return unless @context.viewer&.site_admin?
    @object.stafftools_url
  end

  def viewer_can_report?
    @object.viewer_can_report(@context.viewer)
  end

  def viewer_can_see_delete_button?
    @context.viewer&.site_admin? &&
      @object.viewer_can_delete?(@context.viewer) &&
      @viewer_can_repo_push
  end

  def viewer_can_report_to_maintainer?
    @object.viewer_can_report_to_maintainer(@context.viewer)
  end

  def viewer_relationship
    @object.viewer_relationship(@context.viewer)
  end

  def viewer_can_see_minimize_button?
    @context.viewer&.site_admin? &&
      @viewer_can_minimize &&
      @viewer_can_repo_push
  end

  def viewer_can_see_unminimize_button?
    @context.viewer&.site_admin? &&
      @object.viewer_can_unminimize?(@context.viewer) &&
      @viewer_can_repo_push
  end

  def viewer_can_block_from_org?
    @object.viewer_can_block_from_org?(@context.viewer)
  end

  def viewer_can_unblock_from_org?
    @object.viewer_can_unblock_from_org?(@context.viewer)
  end

  def submitted_at
    @object.respond_to?(:submitted_at) ? @object.submitted_at : nil
  end

  def viewer_can_see?
    !@object.minimized_by_staff? || @object.viewer_can_see?(@context.viewer)
  end

  def minimized_by_staff?
    @object.minimized_by_staff?
  end

  sig { override.returns(T.nilable(T::Array[T::Class[T.anything]])) }
  def self.defined_types
    TYPES
  end
end
