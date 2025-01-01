# typed: true
# frozen_string_literal: true

class Stafftools::Repositories::Actions::CachesController < StafftoolsController
  before_action :ensure_repo_exists

  javascript_bundle :"stafftools-repositories"
  layout "layouts/stafftools/repository/actions"

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Ballast,
    ApplicationRecord::Configurations,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Billing,
    only: [:index]

  def index
    return render_404 unless GitHub.actions_enabled?
    return render_404 unless current_repository.feature_enabled?(:actions_cache_stafftools)

    cache_usage = ActionsCacheUsage.get_repo_cache_usage(current_repository)
    cache_limit = ActionsCacheUsagePolicy.get_repository_cache_usage_policy(current_repository: current_repository)
    is_over_limit = ((cache_usage&.active_caches_size.to_f) / (1024**3)).round(2) > cache_limit
    caches_response = ActionsCacheManagementHelper.get_repo_caches(repo: current_repository)
    caches = []
    if caches_response.call_succeeded?
      caches = caches_response.value.caches
    end
    caches = caches.paginate(page: params[:page], per_page: 10)

    render "stafftools/repositories/actions/caches",
      locals: { current_repository:, cache_usage:, cache_limit:, is_over_limit:, caches: }
  end
end
