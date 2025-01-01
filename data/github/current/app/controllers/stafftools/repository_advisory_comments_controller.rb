# typed: true
# frozen_string_literal: true

class Stafftools::RepositoryAdvisoryCommentsController < StafftoolsController

  before_action :ensure_repository_advisory_exists, only: [:index]
  before_action :ensure_advisory_comment_exists, only: [:show, :database]

  layout "layouts/stafftools/repository/collaboration"

  depends_on_clusters ApplicationRecord::Ballast,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    only: %i[database index show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:database, :show, :index], optional: true

  def index
    @comments = this_repository_advisory.comments.paginate \
      page: params[:page] || 1,
      per_page: 25
    render "stafftools/repository_advisory_comments/index"
  end

  def show
    query = "data.repository_advisory_comment_id:#{this_advisory_comment.id} OR (data.user_content_id:#{this_advisory_comment.id} AND data.user_content_type:#{this_advisory_comment.class} AND action:user_content_edit.*)"
    if driftwood_ade_query?(current_user)
      query = <<~KQL
       webevents
       | where (action startswith "repository_advisory_comment" and repository_advisory_id == #{this_repository_advisory.id} and data.repository_advisory_comment_id == "#{this_advisory_comment.id}")
       or (user_content_id == #{this_advisory_comment.id} and user_content_type == "#{this_advisory_comment.class}" and action startswith "user_content_edit")
     KQL
    end
    fetch_audit_log_teaser(query)

    render("stafftools/repository_advisory_comments/show")
  end

  def database # rubocop:todo GitHub/UseRestfulActions
    render "stafftools/repository_advisory_comments/database"
  end

  private

  memoize def this_advisory_comment
    this_repository_advisory.comments.find_by_id(params[:id])
  end
  helper_method :this_advisory_comment

  def ensure_advisory_comment_exists
    render_404 if this_advisory_comment.nil?
  end

  def ensure_repository_advisory_exists
    render_404 if this_repository_advisory.nil?
  end
end
