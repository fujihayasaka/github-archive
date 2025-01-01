# typed: true
# frozen_string_literal: true

class Stafftools::Repositories::Actions::CachesController < StafftoolsController
  include ActionsCacheControllerMethods

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

    cache_usage = ActionsCacheUsage.get_repo_cache_usage(current_repository)
    cache_limit = ActionsCacheUsagePolicy.get_repository_cache_usage_policy(current_repository: current_repository)
    is_over_limit = ((cache_usage&.active_caches_size.to_f) / (1024**3)).round(2) > cache_limit

    caches = cache_items
    max_allowed_page = [1, (caches[:total_count] / DEFAULT_PER_PAGE.to_f).ceil].max

    if current_page > max_allowed_page
      current_page = max_allowed_page
    end
    caches = caches[:actions_caches]

    render "stafftools/repositories/actions/caches",
      locals: { current_repository:, cache_usage:, cache_limit:, is_over_limit:, caches: }
  end
end
