# typed: true
# frozen_string_literal: true

class Stafftools::DiscussionCommentsController < StafftoolsController

  before_action :ensure_discussion_exists
  before_action :ensure_comment_exists, only: [:show, :database, :nested_comments]

  layout "layouts/stafftools/repository/collaboration"

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    only: [:database]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    only: [:index, :show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show, :index, :database],
    optional: true

  def index
    comments = this_discussion.comments.paginate \
      page: params[:page] || 1,
      per_page: 25

    render("stafftools/discussion_comments/index", locals: {
      comments: comments,
    })
  end

  def show
    conditions = [
      "data.discussion_comment_id:#{this_comment.id}",
      "data.user_content_id:#{this_comment.id} AND data.user_content_type:#{this_comment.class} AND action:user_content_edit.*",
      "data.comment_id:#{this_comment.id} AND data.comment_type:#{this_comment.class}",
    ]
    audit_log_query = conditions.map { |cond| "(#{cond})" }.join(" OR ")
    if driftwood_ade_query?(current_user)
      audit_log_query = <<~KQL
        webevents
        | where data.discussion_comment_id == "#{this_comment.id}"
        or (user_content_id == #{this_comment.id} and user_content_type == "#{this_comment.class}" and action startswith "user_content_edit")
        or (data.comment_id == #{this_comment.id} and data.comment_type == "#{this_comment.class}")
      KQL
    end
    audit_log_data = fetch_audit_log_teaser(audit_log_query)

    notifications_view = Stafftools::RepositoryViews::NotificationsView.new(
      repository: current_repository,
      params: {
        thread: Newsies::Thread.new("Discussion", this_comment.discussion_id || this_comment.id).key,
        comment: Newsies::Comment.to_key(this_comment),
      },
    )

    render("stafftools/discussion_comments/show", locals: {
      notifications_view: notifications_view,
      audit_log_data: audit_log_data,
    })
  end

  def database # rubocop:todo GitHub/UseRestfulActions
    render "stafftools/discussion_comments/database"
  end

  def nested_comments # rubocop:todo GitHub/UseRestfulActions
    comments = this_comment.comments.paginate \
      page: params[:page] || 1,
      per_page: 25

    render("stafftools/discussion_comments/nested_comments", locals: {
      comments: comments,
    })
  end

  private

  memoize def this_comment
    this_discussion.comments.find_by_id(params[:id])
  end
  helper_method :this_comment

  def ensure_comment_exists
    render_404 if this_comment.nil?
  end

end
