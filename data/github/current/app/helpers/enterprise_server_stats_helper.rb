# typed: true
# frozen_string_literal: true

# Helpers for Organization/Business enterprise server stats controllers
module EnterpriseServerStatsHelper
  include Kernel

  class IvalidTimePeriodError < ArgumentError; end
  class InvalidStatNameError < ArgumentError; end

  TIME_PERIOD_KEYS = %w(year month week)

  STATS_CONFIG = {
    issues: {
      metrics: [
        { label: "Total Issues", sub_key: "total_issues" },
        { label: "Open Issues", sub_key: "open_issues" },
        { label: "Closed Issues", sub_key: "closed_issues" }
      ]
    },
    pulls: {
      metrics: [
        { label: "Total Pull Requests", sub_key: "total_pulls" },
        { label: "Merged Pull Requests", sub_key: "merged_pulls" },
        { label: "Mergeable Pull Requests", sub_key: "mergeable_pulls" },
        { label: "Unmergeable Pull Requests", sub_key: "unmergeable_pulls" }
      ]
    },
    repos: {
      metrics: [
        { label: "Total Repos", sub_key: "total_repos" }
      ]
    },
    users: {
      metrics: [
        { label: "All Users", sub_key: "total_users" },
        { label: "Suspended Users", sub_key: "suspended_users" }
      ]
    },
    orgs: {
      metrics: [
        { label: "All Orgs", sub_key: "total_orgs" },
        { label: "All Teams", sub_key: "total_teams" },
        { label: "All Team Members", sub_key: "total_team_members" }
      ]
    }
  }

  STAT_KEYS = STATS_CONFIG.map { |stat_key, _| stat_key.to_s }

  def chart_from_usage_metrics(raw_usage_metrics, stat_key, selected_server, time_period)
    validate_stat_key(stat_key)
    validate_time_period(time_period)

    server_usage_metrics = (raw_usage_metrics || []).filter { |record| selected_server == record["server_id"] }
    transform_stat_data(server_usage_metrics, time_period, stat_key)
  end

  def transform_stat_data(server_usage_metrics, time_period, stat_key)
    stat_config = STATS_CONFIG[stat_key.to_sym]

    rows = []
    hero_stats = []
    stat_config[:metrics].each do |metric_config|
      new_rows = rows_for_metric(server_usage_metrics, stat_key, time_period, metric_config)
      rows.concat(new_rows)

      if !new_rows.empty?
        hero_stats << hero_stat(new_rows, metric_config[:label])
      end
    end

    {
      series: {
        columns: [
          { name: "Date", data_type: "datetime" },
          { name: "Count", data_type: "int" },
          { name: "#{stat_key.titleize} Count", data_type: "nvarchar" }
        ],
        rows: rows.sort_by! { |row| row[0] },
      },
      hero_stats: hero_stats
    }
  end

  def rows_for_metric(usage_metrics, main_key, time_period, metric_config)
    rows = []

    usage_metrics.each do |metric|
      collection_date = DateTime.parse(metric["collection_date"])

      if collection_date >= date_to_check(time_period)
        sub_key = metric_config[:sub_key]
        value = metric["ghe_stats"][main_key][sub_key].to_i
        rows << [collection_date, value, metric_config[:label]]
      end
    end unless usage_metrics.nil?
    rows
  end

  def hero_stat(rows, label)
    # Sort by date column
    rows = rows.sort_by { |row| row[0] }
    oldest_value = rows.first[1]
    newest_value = rows.last[1]
    percent_change = if oldest_value.zero? && newest_value.nonzero?
      # we can't calculate percent change from zero to a non-zero value
      nil
    else
      ((newest_value - oldest_value) / (oldest_value.to_f.nonzero? || 1.0) * 100).round(2)
    end
    { total: newest_value, percent_change: percent_change, label: label }
  end

  def date_to_check(time_period)
    now = DateTime.now
    case time_period
    when "week"
      date_to_check = now.prev_week
    when "month"
      date_to_check = now.prev_month
    when "year"
      date_to_check = now.prev_year
    end
    date_to_check
  end

  def validate_stat_key(stat_key)
    unless STAT_KEYS.include? stat_key
      raise InvalidStatNameError, "'#{stat_key}' is not a valid stat key"
    end
  end

  def validate_time_period(time_period)
    unless TIME_PERIOD_KEYS.include? time_period
      raise IvalidTimePeriodError, "'#{time_period}' is not a valid time period"
    end
  end
end
