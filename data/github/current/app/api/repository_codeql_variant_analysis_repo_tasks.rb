# typed: true
# frozen_string_literal: true

class Api::RepositoryCodeqlVariantAnalysisRepoTasks < Api::App
  include VariantAnalysis::RepositoryResolutionHelper

  before do
    deliver_error! 404 if GitHub.enterprise?
  end

  get "/repositories/:repository_id/code-scanning/codeql/variant-analyses/:codeql_variant_analysis_id/repositories/:variant_analysis_repo_id", operation_id: "code-scanning/get-variant-analysis-repo-task" do
    @route_owner = "@github/code-scanning-secexp"

    controller_repo = ActiveRecord::Base.connected_to(role: :reading) { find_repo! }

    @accepted_scopes = controller_repo.public? ? %w(public_repo repo) : %w(repo)

    control_access :read_multi_repository_variant_analysis,
      resource: controller_repo,
      forbid: controller_repo.public?,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    repo_task = get_repo_task(controller_repo, params)

    deliver :repository_codeql_variant_analysis_repo_task_hash, repo_task
  end

  private

  def get_repo_task(controller_repo, params)
    variant_analysis = CodeqlVariantAnalysis.find_by(
      id: params[:codeql_variant_analysis_id].to_i,
      controller_repo_id: controller_repo.id)
    deliver_error!(404, message: "Variant analysis not found") unless variant_analysis

    repo_task = CodeqlVariantAnalysisRepoTask.find_by(
      codeql_variant_analysis_id: variant_analysis.id,
      repository_id: params[:variant_analysis_repo_id].to_i)

    if repo_task.nil? || !repository_id_accessible?(repo_task.repository_id, current_user, cap_filter)
      deliver_error!(404, message: "Repository not found for variant analysis")
    end

    repo_task
  end
end
