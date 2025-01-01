# typed: true
# frozen_string_literal: true

class Stafftools::RepositoryOrchestrationsController < StafftoolsController
  before_action :ensure_repo_exists

  layout "layouts/stafftools/repository/overview"

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
    # this is a bit gross but temporary
    # we need to look at both repositories and ballast tables because we can
    # toggle between them via a feature flag
    orchestrations = RepositoryOrchestration.most_recent_for_repository(current_repository.id).to_a

    @repository_orchestrations = orchestrations.paginate \
      page: params[:page] || 1,
      per_page: 25

    render "stafftools/repository_orchestrations/index"
  end

  def show
    id = params[:id].to_i
    orchestration = RepositoryOrchestration.where(id: id, repository_id: current_repository.id).first

    render "stafftools/repository_orchestrations/show", locals: { repository_orchestration: orchestration }
  end
end
