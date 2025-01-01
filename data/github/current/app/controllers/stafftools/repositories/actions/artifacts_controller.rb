# typed: true
# frozen_string_literal: true

class Stafftools::Repositories::Actions::ArtifactsController < StafftoolsController
  before_action :ensure_repo_exists

  javascript_bundle :"stafftools-repositories"
  layout "layouts/stafftools/repository/actions"

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Ballast,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Copilot,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::RepositoriesActionsChecks,
    only: [:index]

  def index
    return render_404 unless GitHub.actions_enabled?
    artifacts = Artifact
      .where(repository_id: current_repository.id)
      .includes(:check_suite, check_suite: :workflow_run)
      .order(id: :desc)
      .paginate(page: current_page, per_page: 25)

    artifacts = artifacts.where(name: params[:name]) if params[:name].present?

    render "stafftools/repositories/actions/artifacts", locals: {
      artifacts: artifacts,
    }
  end
end
