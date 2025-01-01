# typed: true
# frozen_string_literal: true

class Issues::Branch::TargetRepositoriesController < IssuesController
  before_action :login_required
  before_action :issue_required

  depends_on_clusters ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Memex,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Spokes,
    optional: false, only: [:index]

  def index
    render Issues::Branch::TargetRepositoryComponent.new(
      query: query,
      selected_repository: current_issue.repository,
      issue: current_issue,
      current_repository: current_repository
    ), layout: false
  end

  private

  def query
    Branches::TargetRepositoryQuery.new(
      selected_repository: current_issue.repository,
      current_user: current_user,
      phrase: params[:q],
      user_session: user_session,
      remote_ip: request&.remote_ip,
      cap_filter: cap_filter,
      user_repos_first: true
    )
  end
end
