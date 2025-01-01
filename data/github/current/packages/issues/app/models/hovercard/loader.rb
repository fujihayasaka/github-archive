# typed: true
# frozen_string_literal: true

class Hovercard::Loader
  include Issue::PrefillHelper
  attr_reader :context

  MAX_LINKED_ISSUES_DISPLAYED = 5

  def self.load_for(issue_or_pr, repository, viewer, cap_filter:, include_notification_contexts: true, comment_id: nil, comment_type: nil, disable_issues_graph: false)
    loader = new(
      issue_or_pr,
      repository,
      viewer,
      cap_filter: cap_filter,
      include_notification_contexts: include_notification_contexts,
      comment_id: comment_id,
      comment_type: comment_type,
      disable_issues_graph: disable_issues_graph
    )

    self.hovercard_adapter(loader)
  end

  def initialize(issue_or_pr, repository, viewer, cap_filter:, include_notification_contexts: true, comment_id: nil, comment_type: nil, disable_issues_graph: false)
    issue = issue_or_pr.is_a?(Issue) ? issue_or_pr : issue_or_pr.issue
    @context = Issue::Adapter::Context.new(issue, repository, viewer, cap_filter: cap_filter, disable_issues_graph: disable_issues_graph)
    @comment_id = comment_id
    @comment_type = comment_type
    @include_notification_contexts = include_notification_contexts
    @pull_request = issue_or_pr unless issue_or_pr.is_a?(Issue)
    @disable_issues_graph = disable_issues_graph

    preload
  end

  def self.hovercard_adapter(loader)
    Hovercard::Adapter::HovercardAdapter.new(loader.context)
  end

  def setup_context
    [
      :comments_by_id,
      :pull_requests_by_id,
      :integrations_by_id,
    ].each do |symbol|
      @context.preload_attr(symbol, {})
    end
  end

  def preload
    setup_context

    load_comment
    load_users
    load_and_attach_integrations
    attach_user_associations
    preload_primary_avatars

    @context.pull_requests_by_id[@context.issue.pull_request_id] = @pull_request if @pull_request

    Promise.all(hovercard_context_promises).then do |values|
      @context.preload_attr(:hovercard_context_involvements, values.compact)
    end.sync

    preload_tracked_in_issues
  end

  private

  def load_comment
    @comment = if @comment_id.nil?
      nil
    elsif @comment_type == IssueOrPullRequestHovercard::ISSUE_COMMENT_TYPE
      @context.issue.comments.find_by(id: @comment_id)
    elsif @comment_type == IssueOrPullRequestHovercard::REVIEW_COMMENT_TYPE
      @pull_request.review_comments.find_by_id(@comment_id)
    elsif @comment_type == IssueOrPullRequestHovercard::REVIEW_TYPE
      @pull_request.reviews.find_by(id: @comment_id)
    end

    @context.comments_by_id[@comment.id] = @comment if @comment
  end

  def load_users
    user_ids = [@context.repository.owner_id, @context.issue.user_id, @comment&.user_id].compact.uniq
    User.where(id: user_ids).index_by(&:id).tap do |users_by_id|
      @context.preload_attr(:users_by_id, users_by_id)
    end
  end

  def load_and_attach_integrations
    bot_ids_to_load = @context.bots.map(&:id).compact
    if bot_ids_to_load.any?
      Issue::Loader::Integrations.load_for_bots(@context, bot_ids: bot_ids_to_load)
      Issue::Loader::Users.new(@context).preload_primary_avatars_for_users(@context.integrations, "integrations")
      Issue::Loader::Integrations.attach_integrations_to_bots(@context, @context.bots)
    end
  end

  def load_tracked_in_issues?
    GitHub.flipper[:extract_checklists].enabled?(@context.viewer)
  end

  def preload_tracked_in_issues
    tracked_in_issues = if @pull_request
      []
    elsif @disable_issues_graph
      []
    else
      redactor = TasklistBlocks::Redactor.new(
        viewer: context.viewer,
        issues: @context.issue.parent_issues,
        cap_filter: @context.cap_filter,
        options: {
          exclude_redacted_issues: true,
        },
      )
      redactor.issues.map do |tracked_issue|
        # these should already be excluded, but this makes sorbet happy
        next if tracked_issue.is_a?(TasklistBlocks::RedactedIssue)
        {
          owner: tracked_issue.owner_display_login,
          repository: tracked_issue.repository_name,
          issue_number: tracked_issue.number,
          issue_url: tracked_issue.url,
          issue_state: tracked_issue.state,
          issue_state_reason: tracked_issue.state_reason,
        }
      end.compact
    end


    tracked_in_issues += if load_tracked_in_issues? && tracked_in_issues.size < MAX_LINKED_ISSUES_DISPLAYED
      tracking_issues = @context.issue
        .displayable_tracking_issues_for(viewer: @context.viewer)
        .take(MAX_LINKED_ISSUES_DISPLAYED - tracked_in_issues.size)

      cap_filtered_tracking_issues = @context.cap_filter.authorized_resources(tracking_issues)
      GitHub::PrefillAssociations.prefill_associations(cap_filtered_tracking_issues, :repository)

      cap_filtered_tracking_issues.map do |tracked_issue|
        {
          owner: tracked_issue.repository.owner_display_login,
          repository: tracked_issue.repository.name,
          issue_number: tracked_issue.number,
          issue_url: tracked_issue.url,
          issue_state: tracked_issue.state,
          issue_state_reason: tracked_issue.state_reason,
        }
      end
    else
      []
    end

    @context.preload_attr(:tracked_in_issues, tracked_in_issues)
  end

  def preload_primary_avatars
    Issue::Loader::Users.new(@context).preload_primary_avatars_for_users(@context.users, "users")
  end

  def attach_user_associations
    # Stripped down version of what is in `Issues::ShowLoader` as we don't want to invoke `comments.latest_user_content_edits`
    prefill_from_exhaustive_available_records(@context.issue, :user, available_records: @context.users)
    prefill_from_exhaustive_available_records(@context.repository, :owner, available_records: @context.users)
    prefill_from_exhaustive_available_records(@context.comments, :user, available_records: @context.users)
    prefill_from_exhaustive_available_records(@context.integrations, :owner, available_records: @context.users)
  end

  def hovercard_context_promises
    return [] if @context.viewer.nil?

    # Check each type of involvement.
    promises = [
      IssueOrPullRequestHovercard::Contexts::ViewerInvolvement.async_resolve(
        issue_or_pull_request: @context.issue,
        viewer: @context.viewer
      ).then do |viewer_involvement|
        Hovercard::Adapter::ViewerInvolvementContext.new(@context, involvement: viewer_involvement) unless viewer_involvement.nil?
      end
    ]

    if @include_notification_contexts
      promises << IssueOrPullRequestHovercard::Contexts::NotificationSubscriptionReason.async_resolve(
        issue_or_pull_request: @context.issue,
        viewer: @context.viewer
      ).then do |viewer_involvement|
        Hovercard::Adapter::GenericInvolvementContext.new(@context, involvement: viewer_involvement) unless viewer_involvement.nil?
      end
    end

    if @context.issue.pull_request?
      begin
        promises << IssueOrPullRequestHovercard::Contexts::ReviewStatus.async_resolve(
          issue_or_pull_request: @pull_request,
          viewer: @context.viewer
        ).then do |viewer_involvement|
          Hovercard::Adapter::ReviewStatusInvolvementContext.new(@context, involvement: viewer_involvement) unless viewer_involvement.nil?
        end
      rescue GitHub::Spokes::ClientError, GitRPC::CommandBusy => e
        # If we can't load the review status, we don't want to block the hovercard from loading.
        Failbot.report(e)
        promises << Promise.resolve(nil)
      end
    end
    promises
  end
end
