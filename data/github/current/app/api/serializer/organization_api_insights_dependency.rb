# typed: true
# frozen_string_literal: true

module Api::Serializer::OrganizationApiInsightsDependency

  def org_api_insights_summary_stats(data, options = {})
    return { total_request_count: 0, rate_limited_request_count: 0 } if data.records.empty?
    stats = data.records.first
    {
      total_request_count: stats["total_request_count"],
      rate_limited_request_count: stats["rate_limited_request_count"]
    }
  end

  def org_api_insights_time_stats(data, options = {})
    stats = data[:stats]

    return [] if stats.records.empty?

    stats.records.map do |d|
      {
        timestamp: d["timestamp"],
        total_request_count: d["total_request_count"],
        rate_limited_request_count: d["rate_limited_request_count"]
      }
    end if stats.records.present?
  end

  def org_api_insights_subject_stats(data, options = {})

    return [] if data[:stats].empty?

    data[:stats].map do |d|
      {
        subject_type: d["subject_type"],
        subject_id: d["subject_id"],
        subject_name: d["subject_name"],
        total_request_count: d["total_request_count"],
        rate_limited_request_count: d["rate_limited_request_count"],
        last_request_timestamp: d["last_request_timestamp"],
        last_rate_limited_timestamp: d["last_rate_limited_timestamp"]
      }
    end

  end

  def org_api_insights_user_stats(data, options = {})

    data[:stats].map do |d|
      out = {
        actor_type: d["actor_type"],
        actor_id: d["actor_id"],
        actor_name: d["actor_name"],
        total_request_count: d["total_request_count"],
        rate_limited_request_count: d["rate_limited_request_count"],
        last_request_timestamp: d["last_request_timestamp"],
        last_rate_limited_timestamp: d["last_rate_limited_timestamp"]
      }

      out[:integration_id] = d["integration_id"] if d["integration_id"].present?
      out[:oauth_application_id] = d["oauth_application_id"] if d["oauth_application_id"].present?

      out
    end

  end

  def org_api_insights_route_stats(data, options = {})

    data[:stats].map do |d|
      out = {
        http_method: d["http_method"],
        api_route: d["api_route"],
        total_request_count: d["total_request_count"],
        rate_limited_request_count: d["rate_limited_request_count"],
        last_request_timestamp: d["last_request_timestamp"],
        last_rate_limited_timestamp: d["last_rate_limited_timestamp"]
      }

      out
    end

  end

end
