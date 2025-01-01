# typed: false
# frozen_string_literal: true

class UserContentEditsController < ApplicationController
  include PlatformHelper

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Repositories,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Ballast,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    only: [:show]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Repositories,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Configurations,
    ApplicationRecord::Ballast,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    only: [:show_edit_history]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    only: [:show_edit_history_log]

  depends_on_clusters ApplicationRecord::Copilot,
      only: [:show, :show_edit_history],
      optional: true

  class UnknownControllerActionExternalIdentityOrganization < StandardError; end

  before_action :login_required, only: [:destroy]

  helper_method :can_delete_user_content_edit?

  DISCUSSION_EDIT_CLASSES = [
    DiscussionEdit,
    DiscussionCommentEdit,
  ]

  private def target_for_conditional_access
    user_content = case params[:action]
    when "show", "destroy"
      user_content_edit&.user_content
    when "show_edit_history", "show_edit_history_log"
      comment
    else
      # Whenever a new route is added to this controller it needs to be
      # accounted for in this method
      raise UnknownControllerActionExternalIdentityOrganization
    end

    return :no_target_for_conditional_access unless user_content # rubocop:disable GitHub/SpecifyTargetForConditionalAccess

    owner = case user_content
    when DiscussionItem
      user_content.organization
    when Gist, GistComment
      user_content.user
    when PullRequest, PullRequestReview, PullRequestReviewComment, CommitComment, RepositoryAdvisory, RepositoryAdvisoryComment, DiscussionComment, Discussion
      user_content.repository.owner
    when IssueComment
      user_content.issue.owner
    when Issue
      user_content.owner
    else
      error = TypeError.new("Unexpected user content type '#{user_content.class}'")
      raise error
    end

    # It is possible that a user can be deleted after adding the comment
    # Otherwise we will have this #target_for_conditional_access failure:
    # ArgumentError: resource UserContentEditsController#(id: unknown) returned nil as target_for_conditional_access
    # :no_target_for_conditional_access is used to signal we can skip things like ip enforcement, saml, etc
    # It seems worth explicitly returning that here when we know we don't have an owner and therefore could not enforce those things.
    # Since the method being edited here already returned :no_target_for_conditional_access in certain cases
    # it seems consistent to return it in this case as well.
    owner || :no_target_for_conditional_access # rubocop:todo GitHub/SpecifyTargetForConditionalAccess
  end

  def show
    respond_to do |format|
      format.html do
        if request.xhr? && user_content_edit
          if DISCUSSION_EDIT_CLASSES.include?(user_content_edit.class)
            render Discussions::EditHistory::DiffComponent.new(
              edit: user_content_edit,
            ), layout: false
          else
            render partial: "comments/comment_edit_history_diff", locals: { user_content_edit: user_content_edit }
          end
        else
          render_404
        end
      end
    end
  end

  def show_edit_history # rubocop:todo GitHub/UseRestfulActions
    respond_to do |format|
      format.html do
        render_404 and return unless request.xhr? && comment
        render_404 and return unless comment.viewer_can_read_user_content_edits?(current_user)

        render Comments::CommentEditHistoryComponent.new(comment: comment, author: comment.user), layout: false
      end
    end
  end

  def show_edit_history_log # rubocop:todo GitHub/UseRestfulActions
    respond_to do |format|
      format.html do
        render_404 and return unless request.xhr? && comment
        render_404 and return unless comment.viewer_can_read_user_content_edits?(current_user)

        render Comments::CommentEditHistoryLogComponent.new(comment: comment), layout: false
      end
    end
  end

  def destroy
    return render_404 unless user_content_edit

    if site_admin? || can_delete_user_content_edit?(user_content_edit)
      user_content_edit.soft_delete!(current_user)
    else
      flash[:error] = "Unable to delete edit history"
    end

    redirect_to :back
  end

  private

  def user_content_edit
    return @user_content_edit if defined?(@user_content_edit)
    global_id = params[:id]
    user_content_edit = if Platform::Helpers::GlobalId.next?(global_id)
      id = Platform::Helpers::GlobalId.parse(global_id)
      Platform::Objects::UserContentEdit.load_from_next_global_id(id).sync
    else
      _, id = Platform::Helpers::NodeIdentification.from_global_id(global_id)
      Platform::Objects::UserContentEdit.load_from_global_id(id).sync
    end
    @user_content_edit = user_content_edit&.viewer_can_read?(current_user) ? user_content_edit : nil
  rescue Platform::Errors::NotFound
    @user_content_edit = nil
  end

  def comment
    return @comment if defined?(@comment)

    @comment = typed_object_from_id([Platform::Interfaces::Comment], params[:comment_id])
  rescue Platform::Errors::NotFound
    @comment = nil
  end

  def content
    return @content if defined?(@content)
    @content = typed_object_from_id([Platform::Interfaces::Comment], params[:content_id])
  # NameError is happenong here as a response to Errors not being defined, but it is the notfound error
  rescue NameError, Platform::Errors::NotFound
    nil
  end

  # Checks if a user can delete the user content edit
  # For gist comment edits we are checking adminable by,
  # but for the rest we check against repo permissions
  def can_delete_user_content_edit?(user_content_edit)
    return false unless logged_in?
    user_content_edit.viewer_can_delete?(current_user)
  end
end
