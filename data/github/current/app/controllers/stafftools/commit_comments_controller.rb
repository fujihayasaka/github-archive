# typed: true
# frozen_string_literal: true

class Stafftools::CommitCommentsController < StafftoolsController
  before_action :ensure_comment_exists, only: [:show]

  layout "layouts/stafftools/repository/collaboration", except: :destroy

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Repositories,
    ApplicationRecord::Ballast,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show],
    optional: true

  def show
    render "stafftools/commit_comments/show"
  end

  def destroy
    comment = CommitComment.find_by(id: params[:comment_id])
    T.must(comment).destroy

    head 200
  end

  private

  memoize def this_comment
    CommitComment.find_by(id: params[:id])
  end
  helper_method :this_comment

  memoize def this_user
    this_comment.try(:user)
  end
  helper_method :this_user

  memoize def current_repository
    this_comment.try(:repository)
  end

  def ensure_comment_exists
    render_404 if this_comment.nil?
  end
end
