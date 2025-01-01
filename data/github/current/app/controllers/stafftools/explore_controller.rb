# typed: true
# frozen_string_literal: true

# biztools for explore stuff
class Stafftools::ExploreController < StafftoolsController
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Repositories,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Ballast,
    ApplicationRecord::Configurations,
    ApplicationRecord::Billing,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index],
    optional: true

  TRENDING_CACHE_PERIODS = %w(daily weekly monthly)

  def index
    render "stafftools/explore/index"
  end

  def queue_trending # rubocop:todo GitHub/UseRestfulActions
    period = TRENDING_CACHE_PERIODS.include?(params[:period]) ? params[:period] : "all"

    if period == "all"
      TRENDING_CACHE_PERIODS.each do |cache_period|
        CalculateTrendingReposJob.perform_later(cache_period)
        CalculateTrendingUsersJob.perform_later(cache_period)
      end
    else
      CalculateTrendingReposJob.perform_later(period)
      CalculateTrendingUsersJob.perform_later(period)
    end

    flash[:notice] = "Calculating #{period} trending repositories and users. This could take a few minutes."
    redirect_to stafftools_explore_path
  end

  private

  helper_method :trending_cache_set_time

  def trending_cache_set_time(type, period)
    cache_key = "trending:#{type}:query:#{period}:time"
    Time.at(Explore::Kv.store.get(cache_key).value!.to_i).to_datetime
  end
end
