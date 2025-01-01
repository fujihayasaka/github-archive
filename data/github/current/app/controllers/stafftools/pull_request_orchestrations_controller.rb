# typed: true
# frozen_string_literal: true

class Stafftools::PullRequestOrchestrationsController < StafftoolsController
  before_action :ensure_repo_exists

  layout "layouts/stafftools/repository/collaboration"

  # note: this list of clusters is copied from the repository orchestration controller,
  # and has not yet been validated for correctness.
  depends_on_clusters ApplicationRecord::Mysql1,
  ApplicationRecord::IamAbilities,
  ApplicationRecord::Repositories,
  ApplicationRecord::Ballast,
  ApplicationRecord::Collab,
  ApplicationRecord::Mysql2,
  ApplicationRecord::NotificationsEntries,
  ApplicationRecord::Mysql5,
  ApplicationRecord::IssuesPullRequests,
  ApplicationRecord::Configurations,
  ApplicationRecord::Billing,
  ApplicationRecord::Spokes,
  only: [:show, :index]

  depends_on_clusters ApplicationRecord::Copilot,
  only: [:index, :show], optional: true

  def index
    orchestrations = PullRequestOrchestration.where(repository: current_repository)

    @orchestrations = orchestrations.paginate \
      page: params[:page] || 1,
      per_page: 25

    render "stafftools/pull_request_orchestrations/index"
  end

  def show
    id = params[:id].to_i
    orchestration = PullRequestOrchestration.where(id: id, repository_id: current_repository.id).first

    render "stafftools/pull_request_orchestrations/show", locals: { orchestration: orchestration }
  end
end
