# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class CalculateTrendingUsersJob < ApplicationJob
  queue_as :calculate_trending_users

  retry_on_dirty_exit

  def perform(period)
    GitHub.dogstats.distribution_time("calculate_trending_users", tags: ["action:calculate", "type:#{period}"]) do
      calculate(period)
    end

  rescue => error # rubocop:todo Lint/RescueException
    Failbot.report(error)
    raise
  end

  def self.clear_cache(period)
    GitHub.cache.delete("trending:users:query:#{period}")
  end

  def calculate(period)
    self.class.clear_cache(period)

    users = Trending.users({
      period: period,
      from_job: true,
    })
  end
end
