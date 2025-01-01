# typed: true
# frozen_string_literal: true

class Stafftools::CommentsController < StafftoolsController
  before_action :ensure_user_exists, except: [:minimize, :unminimize, :destroy]

  include PlatformHelper

  depends_on_clusters ApplicationRecord::Ballast,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Spokes,
    optional: false, only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index], optional: true

  rescue_from Platform::Errors::NotFound do |_error|
    T.bind(self, Stafftools::CommentsController)

    flash[:error] = "Comment not found."
    redirect_to :back
  end

  def index
    @comments = Stafftools::RecentComments.for_user this_user

    case this_user.site_admin_context
    when "organization"
      render "stafftools/comments/index", layout: "stafftools/organization/collaboration"
    when "user"
      render "stafftools/comments/index", layout: "layouts/stafftools/user/collaboration"
    else
      render_404
    end
  end

  def minimize # rubocop:todo GitHub/UseRestfulActions
    return false unless site_admin?

    comment = find_comment

    if comment.async_minimizable_by?(current_user).sync
      success = comment.set_minimized(current_user,
        params[:minimized_reason],
        params[:classifier],
        comment.user || User.ghost,
        true)
    end

    if success
      flash[:notice] = "Comment was successfully minimized."
    else
      message = comment.errors.full_messages.join(", ")
      flash[:error] = message
    end

    redirect_to :back
  end

  def unminimize # rubocop:todo GitHub/UseRestfulActions
    return false unless site_admin?

    comment = find_comment

    success = false
    if comment.async_unminimizable_by?(current_user).sync
      success = comment.set_unminimized(current_user,
        params[:minimized_reason],
        comment.user || User.ghost,
        true)
    end

    if success
      flash[:notice] = "Comment was successfully unminimized."
    else
      message = comment.errors.full_messages.join(", ")
      flash[:error] = message
    end

    redirect_to :back
  end

  def destroy
    return false unless site_admin?

    type_name, id = Platform::Helpers::NodeIdentification.from_global_id(params[:id])
    if type_name == "IssueComment"
      comment = ::IssueComment.find_by(id: id)
    elsif type_name == "GistComment" && GitHub.enterprise?
      # This is a specific fix, because id are prefixes in enterprise
      comment = ::GistComment.find_by(id: id.rpartition(":").last)
    elsif type_name == "GistComment" && !GitHub.enterprise?
      comment = ::GistComment.find_by(id: id)
    elsif type_name == "DiscussionComment"
      comment = ::DiscussionComment.find_by(id: id)
    elsif type_name == "RepositoryAdvisoryComment"
      comment = ::RepositoryAdvisoryComment.find_by(id: id)
    end

    if comment && comment.async_viewer_can_delete?(current_user).sync && comment.destroy
      flash[:notice] = "Comment was deleted."
    else
      flash[:error] = "Could not delete comment."
    end

    redirect_to stafftools_path
  end

  private

  def find_comment
    typed_object_from_id([Platform::Interfaces::Comment], params.fetch(:comment_id))
  end
end
