# typed: true
# frozen_string_literal: true

class Stafftools::DiscussionsController < StafftoolsController
  include DiscussionsStafftoolsRoutesHelper

  before_action :ensure_repo_exists
  before_action :ensure_discussion_exists, except: [:index]

  layout "layouts/stafftools/repository/collaboration"

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Configurations,
    ApplicationRecord::Billing,
    only: [:index, :show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index, :show], optional: true

  def index
    discussions = current_repository.discussions.order("id DESC").paginate(
      page: params[:page] || 1,
      per_page: 25,
    )

    render "stafftools/discussions/index", locals: {
      discussions: discussions,
      category_limit_override: DiscussionCategory::LimitOverride.for(current_repository),
    }
  end

  def show
    conditions = [
      "data.discussion_id:#{this_discussion.id}",
      "data.user_content_id:#{this_discussion.id} AND data.user_content_type:#{this_discussion.class} AND action:user_content_edit.*",
    ]
    audit_log_query = conditions.map { |cond| "(#{cond})" }.join(" OR ")
    if GitHub.driftwood_ade_queries_enabled?
      audit_log_query = <<~KQL
        webevents
        | where data.discussion_id == "#{this_discussion.id}"
        or (user_content_id == #{this_discussion.id} and user_content_type == "#{this_discussion.class}" and action startswith "user_content_edit")
      KQL
    end
    audit_log_data = fetch_audit_log_teaser(audit_log_query)

    notifications_view = Stafftools::RepositoryViews::NotificationsView.new(
      repository: current_repository,
      params: {
        thread: Newsies::Thread.new("Discussion", this_discussion.id).key,
        comment: Newsies::Comment.to_key(this_discussion),
      },
    )

    render "stafftools/discussions/show", locals: {
      notifications_view: notifications_view,
      audit_log_data: audit_log_data,
    }
  end

  def database # rubocop:todo GitHub/UseRestfulActions
    respond_to do |format|
      format.html do
        render "stafftools/discussions/database"
      end
    end
  end

  def destroy
    if this_discussion.destroy
      discussion_num = this_discussion.number

      instrument \
        "staff.delete_discussion",
        user: current_repository.owner,
        repo: current_repository,
        note: "Deleted discussion #{current_repository.nwo}##{discussion_num}"

      flash[:notice] = "Discussion ##{this_discussion.number} deleted"
    else
      flash[:error] = this_discussion.errors.full_messages
    end

    redirect_to gh_stafftools_repository_discussions_path(current_repository)
  end

  def lock # rubocop:todo GitHub/UseRestfulActions
    this_discussion.lock(actor: current_user)

    redirect_to gh_stafftools_repository_discussion_path(this_discussion)
  end

  def unlock # rubocop:todo GitHub/UseRestfulActions
    this_discussion.unlock(actor: current_user)

    redirect_to gh_stafftools_repository_discussion_path(this_discussion)
  end
end
