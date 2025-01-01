# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class CalculateTrendingReposJob < ApplicationJob
  queue_as :calculate_trending_repos

  retry_on_dirty_exit

  def perform(period)
    GitHub.dogstats.distribution_time("calculate_trending_repos", tags: ["action:calculate", "type:#{period}"]) do
      calculate(period)
    end
  end

  def self.clear_cache(period)
    GitHub.cache.delete("trending:repos:query:#{period}")
  end

  def calculate(period)
    self.class.clear_cache(period)

    begin
      trending_ids = Trending.repo_ids({
        period: period,
        from_job: true,
      })

      repositories = Repository.where(id: trending_ids.map(&:first)).index_by(&:id)

      repos = trending_ids.map do |repo_id, val|
        [repositories[repo_id], val]
      end
    rescue => error # rubocop:todo Lint/GenericRescue
      Failbot.report(error)
      raise
    end
  end
end
