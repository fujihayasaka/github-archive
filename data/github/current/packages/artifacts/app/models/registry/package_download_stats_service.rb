# typed: false
# frozen_string_literal: true

module Registry
  module PackageDownloadStatsService

    # This is the maximum number of downloads a public package's version can have before
    # it makes that package/version impossible to delete
    PUBLIC_VERSION_DELETE_LIMIT = 5000

    # This is the maximum number of downloads any immutable actions container package version can have before
    # it makes that package version impossible to delete. This applies to all packages regardless of repository visibility
    MAX_DOWNLOAD_COUNT_BEFORE_DELETE_RESTRICTION_FOR_IMMUTABLE_ACTIONS = 5000

    def downloads_today
      downloads_in_range(Time.now.beginning_of_day, Time.now.end_of_day)
    end

    def downloads_last_thirty_days
      downloads_in_range(30.days.ago.beginning_of_day, Time.now.end_of_day)
    end

    def downloads_this_week
      downloads_in_range(Time.now.beginning_of_week, Time.now.end_of_week)
    end

    def downloads_this_month
      downloads_in_range(Time.now.beginning_of_month, Time.now.end_of_month)
    end

    def downloads_this_year
      downloads_in_range(Time.now.beginning_of_year, Time.now.end_of_year)
    end

    def downloads_total_count
      downloads_in_range(nil, nil)
    end
  end
end
