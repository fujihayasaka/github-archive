# typed: true
# frozen_string_literal: true

class Stafftools::Repositories::Checks::CheckSuiteController < StafftoolsController
  before_action :ensure_repo_exists

  javascript_bundle :"stafftools-repositories"
  layout "layouts/stafftools/repository/actions"

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Ballast,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Collab,
    only: [:index]

  def index
    check_suite_id = params[:check_suite_id].to_i
    check_suite = Checks.domain.check_suites.for_id(check_suite_id, repository_id: current_repository.id)
    return render_404 unless check_suite.present?

    if check_suite.actions_app?
      flash[:notice] = "Redirecting to Actions workflow execution page since this is an Actions check suite"
      return redirect_to actions_workflow_execution_stafftools_repository_path(check_suite_id:)
    end

    github_app = check_suite.github_app
    check_runs = check_suite.check_runs

    render "stafftools/repositories/checks/check_suite",
      locals: { current_repository:, check_suite:, check_runs:, github_app: }
  end
end
