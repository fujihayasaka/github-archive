# typed: true
# frozen_string_literal: true

class Issues::Branch::SourceBranchController < IssuesController
  before_action :login_required
  # We're not consuming the issue in this controller but it's convenient to
  # we're using this to render a 404 if the issue is not found
  before_action :issue_required
  before_action :writable_repository_required

  depends_on_clusters ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Memex,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::RepositoriesPushes,
    ApplicationRecord::Spokes,
    optional: false, only: [:new]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:new], optional: true

  # Renders a "refs/selector" as part of the create branch for issue dialog.
  def new
    render(Branch::SourceBranch::BranchSelectComponent.new(repository: repository), layout: false)
  end

  private

  memoize def repository
    Repositories::Public.find_active!(params[:branch_repository_id])
  end

  # current_repository is the one tied to the issue, the one we're finding
  # is a different one writable by the current user
  def writable_repository_required
    render_404 unless repository&.writable_by?(current_user)
  end
end
