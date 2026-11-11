# typed: true
# frozen_string_literal: true

class Actions::BranchesController < AbstractRepositoryController
  include ::ActionsControllerMethods

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::Configurations,
    ApplicationRecord::Spokes,
    only: [:index]

  param_encoding :index, :q, "ASCII-8BIT"

  def index
    is_lab = params[:lab] == "true"
    search_query = params[:q].to_s

    if !search_query.empty?
      branches = current_repository.heads.substring_filter(substring: search_query, limit: 100)
    else
      branches = current_repository.heads.refs_with_default_first
    end
    branches.map! do |branch|
      {
        name: branch.name,
        default: branch.default_branch?
      }
    end

    respond_to do |format|
      format.any(:html, :html_fragment) do
        render "actions/branches/index",
          layout: false,
          formats: [:html, :html_fragment],
          locals: {
            selected_filename: params[:selected_filename],
            is_lab: is_lab,
            branches: branches,
            workflow_run_filters: workflow_run_filters
          }
      end

      format.json do
        render json: branches
      end
    end
  end

  def select # rubocop:todo GitHub/UseRestfulActions
    branches = current_repository.actions_check_suites.distinct.reorder(:head_branch).pluck(:head_branch).reject(&:blank?).map { |b| strip_branch_prefix(b) }.uniq

    render "actions/branches/select",
      layout: false,
      locals: {
        branches: branches,
        selected_branch: params[:branch],
      }
  end
end
