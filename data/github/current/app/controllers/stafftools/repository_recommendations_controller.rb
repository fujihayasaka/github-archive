# typed: true
# frozen_string_literal: true

class Stafftools::RepositoryRecommendationsController < StafftoolsController
  before_action :discover_repos_dashboard_required
  layout "layouts/stafftools/repository/overview"

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Ballast,
    ApplicationRecord::Spokes,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index],
    optional: true

  def index
    return render_404 unless current_repository

    recommendation = ::RepositoryRecommendation.new(repository: current_repository)
    render "stafftools/repository_recommendations/index", locals: {
      recommendation: recommendation,
    }
  end

  def opt_out # rubocop:todo GitHub/UseRestfulActions
    recommendation = RepositoryRecommendation.new(repository: current_repository)
    recommendation.opt_out(actor: current_user)

    redirect_to stafftools_repository_recommendations_path(params[:user_id], params[:repository_id])
  end

  def opt_in # rubocop:todo GitHub/UseRestfulActions
    recommendation = RepositoryRecommendation.new(repository: current_repository)
    recommendation.opt_in(actor: current_user)

    redirect_to stafftools_repository_recommendations_path(params[:user_id], params[:repository_id])
  end
end
