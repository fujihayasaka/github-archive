# typed: true
# frozen_string_literal: true

class Stafftools::Repositories::Checks::OverviewController < StafftoolsController
  before_action :ensure_repo_exists

  javascript_bundle :"stafftools-repositories"
  layout "layouts/stafftools/repository/actions"

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::RepositoriesActionsChecks,
    only: [:index]

  def index
    check_suite_id = (params[:check_suite_query] || "").strip
    unless check_suite_id.empty?
      check_suite = Checks.domain.check_suites.for_id(check_suite_id.to_i, repository_id: current_repository.id)

      if check_suite.nil?
        flash[:error] = "No check suite found for the given id in this repository"
      else
        if check_suite.actions_app?
          flash[:notice] = "Redirecting to Actions workflow execution page since this is an Actions check suite"
          return redirect_to actions_workflow_execution_stafftools_repository_path(check_suite_id: check_suite_id)
        else
          return redirect_to check_suite_overview_stafftools_repository_path(check_suite_id: check_suite.id)
        end
      end
    end

    check_run_id = (params[:check_run_query] || "").strip
    unless check_run_id.empty?
      check_run = Checks.domain.check_runs.for_id(check_run_id.to_i, repository_id: current_repository.id)

      if check_run.nil?
        flash[:error] = "No check run with id #{check_run_id} was found in this repository"
      else
        check_suite = check_run.check_suite
        if check_suite.nil?
          flash[:error] = "Check run #{check_run_id} appears orphaned as its parent check suite ##{check_run.check_suite_id} is missing"
        else
          if check_suite.actions_app?
            flash[:notice] = "Redirecting to Actions workflow execution page since check run #{check_run_id} originates from an Actions check suite"
            return redirect_to actions_workflow_execution_stafftools_repository_path(check_suite_id: check_suite.id)
          else
            return redirect_to check_suite_overview_stafftools_repository_path(check_suite_id: check_suite.id)
          end
        end
      end
    end

    actions_github_app_id = GitHub.launch_github_app&.id
    actions_review_lab_app_id = GitHub.launch_lab_github_app&.id
    latest_check_suites = Checks.domain.check_suites.latest_ids(current_repository.id, github_app_ids_to_exclude: [actions_github_app_id, actions_review_lab_app_id].compact)

    render "stafftools/repositories/checks/overview",
      locals: { current_repository:, latest_check_suites: }
  end
end
