# typed: true
# frozen_string_literal: true

class Actions::CacheBranchesController < AbstractRepositoryController
  include ::ActionsCacheControllerMethods
  include ::ActionsControllerMethods

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::Configurations,
    only: [:index]

  def index
    branches = current_repository.actions_check_suites.distinct.reorder(:head_branch).pluck(:head_branch).reject(&:blank?).map { |b| strip_branch_prefix(b) }.uniq

    respond_to do |format|
      format.html do
        render "actions/cache/branches/index",
          layout: false,
          locals: {
            cache_item_filters: cache_item_filters,
            branches: branches,
          }
      end

      format.json do
        render json: branches
      end
    end
  end
end
