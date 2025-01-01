# typed: true
# frozen_string_literal: true

class CommentPartialsController < AbstractRepositoryController
  include ShowPartial
  include TimelineHelper

  depends_on_clusters ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Spokes,
    optional: false, only: [:block_from_comment_modal]

  depends_on_clusters ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Copilot,
    ApplicationRecord::Iam,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Memex,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Notify,
    ApplicationRecord::Repositories,
    ApplicationRecord::Spokes,
    optional: false, only: [:timeline_issue_comment]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:block_from_comment_modal], optional: true

  POSSIBLE_COMMENT_TYPES = [
    Platform::Objects::Issue,
    Platform::Objects::PullRequest,
    Platform::Objects::CommitComment,
    Platform::Objects::IssueComment,
    Platform::Objects::PullRequestReview,
    Platform::Objects::PullRequestReviewComment,
    Platform::Objects::RepositoryAdvisoryComment,
  ].freeze

  layout false

  before_action :login_required
  before_action :find_comment, only: [:block_from_comment_modal, :timeline_issue_comment]
  before_action :ensure_can_manage_blocked_users, only: [:block_from_comment_modal]
  before_action :find_issue_comment_adapter, only: [:timeline_issue_comment]

  def block_from_comment_modal # rubocop:todo GitHub/UseRestfulActions
    respond_to do |format|
      format.html do
        render Comments::BlockFromCommentModalComponent.new(comment: current_comment), layout: false
      end
    end
  end

  def timeline_issue_comment # rubocop:todo GitHub/UseRestfulActions
    respond_to do |format|
      format.html do
        render partial: "timeline/issue_comment",
          locals: {
            issue_comment: current_issue_comment_adapter,
            deferred_comment_actions: false,
            deferred_edit_form: false
          }
      end
    end
  end

  private

  def ensure_can_manage_blocked_users
    render_404 unless current_repository.owner.blocked_users_manageable_by?(current_user)
  end

  def find_issue_comment_adapter
    head :not_found unless current_comment.is_a?(IssueComment)
  end

  memoize def current_issue_comment_adapter
    loader = Issue::Loader::CommentLoader.new(
      current_comment.issue,
      current_comment.issue.repository,
      current_user,
      comment: current_comment,
      cap_filter: cap_filter
    )

    issue_adapter = Issue::Loader::CommentLoader.issue_adapter(loader)
    Issue::Adapter::CommentAdapter.new(loader.context, comment_id: current_comment.id, issue_adapter: issue_adapter)
  end

  memoize def current_comment
    typed_object_from_id(POSSIBLE_COMMENT_TYPES, params[:id])
  rescue Platform::Errors::NotFound
    nil
  end

  # TODO: Eventually we may shift away from `global_relay_id`s being the ones passed in, to database ID's.
  # This would require a change in parameters to determine the comment type, rather than using the `global_relay_id`
  def find_comment
    return head :not_found if current_comment.nil?

    if current_comment.respond_to?(:repository_id)
      return head :not_found unless current_comment.repository_id == current_repository.id
    end

    head :not_found if !current_comment.readable_by?(current_user) || current_user.blocked_by?(current_comment.user)
  end

  def route_supports_advisory_workspaces?
    action_name == "timeline_issue_comment"
  end
end
