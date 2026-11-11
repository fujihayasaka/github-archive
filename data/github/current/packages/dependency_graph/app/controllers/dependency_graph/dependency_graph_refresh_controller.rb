# typed: true
# frozen_string_literal: true

module DependencyGraph
  class DependencyGraphRefreshController < AbstractRepositoryController
    include ActionView::Helpers::DateHelper

    depends_on_clusters ApplicationRecord::Mysql1,
      ApplicationRecord::IamAbilities,
      ApplicationRecord::Repositories,
      ApplicationRecord::Collab,
      ApplicationRecord::Configurations,
      ApplicationRecord::SecurityProductsEnablement

    before_action :can_manage_security_products?
    before_action :dependency_graph_enabled?

    def index
      manager = DependencyGraph::DataRefreshManager.new(current_repository)

      if manager.on_cooldown?
        flash[:error] = "Refresh not queued, you must wait to refresh again. Please try again later."
      else
        flash[:message] = "Refresh queued. It may take several minutes for changes to be reflected on the dependency graph."
        manager.request_refresh!(actor: current_user)
      end

      redirect_to network_dependencies_path(
        user_id: current_repository.owner.display_login,
        repository: current_repository.name
      )
    end

    private

    def can_manage_security_products?
      render_404 unless SecurityProduct::Permissions::RepoAuthz.new(current_repository, actor: current_user).can_manage_repo_security_products?
    end

    def dependency_graph_enabled?
      render_404 unless current_repository.dependency_graph_enabled?
    end
  end
end
