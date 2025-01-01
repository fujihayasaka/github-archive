# typed: true
# frozen_string_literal: true

class Stafftools::IssueCommentsController < StafftoolsController

  before_action :ensure_issue_exists, only: [:index, :first]
  before_action :ensure_comment_exists, only: [:show, :database]

  layout "layouts/stafftools/repository/collaboration"

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
    optional: false, only: [:database, :index, :first, :show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index, :database, :first, :show],
    optional: true

  def index
    @comments = this_issue.comments.paginate \
      page: params[:page] || 1,
      per_page: 25
    render "stafftools/issue_comments/index"
  end

  def show
    query = "data.issue_comment_id:#{this_comment.id} OR (data.user_content_id:#{this_comment.id} AND data.user_content_type:#{this_comment.class} AND action:user_content_edit.*)"
    if driftwood_ade_query?(current_user)
      query = <<~KQL
        webevents
        | where (action startswith "issue_comment" and issue_id == #{this_issue.id} and data.issue_comment_id == "#{this_comment.id}")
        or (user_content_id == #{this_comment.id} and user_content_type == "#{this_comment.class}" and action startswith "user_content_edit")
      KQL
    end
    fetch_audit_log_teaser(query)

    notifications_view = Stafftools::RepositoryViews::NotificationsView.new(
      repository: this_comment.repository,
      params: {
        thread: Newsies::Thread.new("Issue", this_comment.try(:issue_id) || this_comment.id).key,
        comment: Newsies::Comment.to_key(this_comment),
      },
    )

    render("stafftools/issue_comments/show", locals: { notifications_view: notifications_view })
  end

  def first # rubocop:todo GitHub/UseRestfulActions
    query = "(data.issue_id:#{this_issue.id} _missing_:data.issue_comment_id) OR (data.user_content_id:#{this_issue.id} AND data.user_content_type:#{this_issue.class} AND action:user_content_edit.*)"
    if driftwood_ade_query?(current_user)
      query = <<~KQL
        webevents
        | where (issue_id == #{this_issue.id} and data.issue_comment_id == "")
        or (user_content_id == #{this_issue.id} and user_content_type == "#{this_issue.class}" and action startswith "user_content_edit.")
      KQL
    end
    fetch_audit_log_teaser(query)

    notifications_view = Stafftools::RepositoryViews::NotificationsView.new(
      repository: this_issue.repository,
      params: {
        thread: Newsies::Thread.new("Issue", this_issue.id).key,
        comment: Newsies::Comment.to_key(this_issue),
      },
    )
    render("stafftools/issue_comments/first", locals: { notifications_view: notifications_view })
  end

  def database # rubocop:todo GitHub/UseRestfulActions
    render "stafftools/issue_comments/database"
  end

  private

  memoize def this_comment
    this_issue.comments.find_by_id(params[:id])
  end
  helper_method :this_comment

  def ensure_comment_exists
    render_404 if this_comment.nil?
  end

end
