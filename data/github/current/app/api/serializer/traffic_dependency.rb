# typed: true
# frozen_string_literal: true

module Api::Serializer::TrafficDependency
  def insights_client_traffic_referrers_hash(insights_response, options = {})
    traffic_data = insights_response[:traffic_data]
    return [] if traffic_data.nil?

    traffic_data[:top_referrers].map do |referrer|
      {
          "referrer" => referrer[:referrer],
          "count"    => referrer[:num_page_views],
          "uniques"  => referrer[:num_unique_viewers],
      }
    end
  end

  def insights_client_traffic_contents_hash(insights_response, options = {})
    traffic_data = insights_response[:traffic_data]
    return [] if traffic_data.nil?

    traffic_data[:top_content].map do |content|
      {
          "path"    => content[:path],
          "title"   => content[:title],
          "count"   => content[:num_page_views],
          "uniques" => content[:num_unique_viewers],
      }
    end
  end

  def insights_client_traffic_views_hash(insights_response, options = {})
    traffic_data = insights_response[:traffic_data]
    return { "count" => 0, "uniques" => 0, "views" => [] } if traffic_data.nil?

    utc = Time.find_zone("UTC")
    {
      "count"   => traffic_data[:summary_14d][:page_views][:num_page_views],
      "uniques" => traffic_data[:summary_14d][:page_views][:num_unique_viewers],
      "views" => traffic_data[:daily_metrics].map do |dm|
        {
          "timestamp" => utc.strptime(dm[:day], "%Y-%m-%d").iso8601,
          "count"     => dm[:page_views][:num_page_views],
          "uniques"   => dm[:page_views][:num_unique_viewers],
        }
      end
    }
  end

  def insights_client_traffic_views_weekly_hash(insights_response, options = {})
    traffic_data = insights_response[:traffic_data]
    return { "count" => 0, "uniques" => 0, "views" => [] } if traffic_data.nil?

    utc = Time.find_zone("UTC")
    {
      "count"   => traffic_data[:summary_14d][:page_views][:num_page_views],
      "uniques" => traffic_data[:summary_14d][:page_views][:num_unique_viewers],
      "views" => traffic_data[:weekly_metrics].map do |dm|
        {
          "timestamp" => utc.strptime(dm[:day], "%Y-%m-%d").iso8601,
          "count"     => dm[:page_views][:num_page_views],
          "uniques"   => dm[:page_views][:num_unique_viewers],
        }
      end
    }
  end

  def insights_client_traffic_clones_hash(insights_response, options = {})
    traffic_data = insights_response[:traffic_data]
    return { "count" => 0, "uniques" => 0, "clones" => [] } if traffic_data.nil?

    utc = Time.find_zone("UTC")
    {
      "count"   => traffic_data[:summary_14d][:clones][:num_clones],
      "uniques" => traffic_data[:summary_14d][:clones][:num_unique_cloners],
      "clones" => traffic_data[:daily_metrics].map do |dm|
        {
          "timestamp" => utc.strptime(dm[:day], "%Y-%m-%d").iso8601,
          "count"     => dm[:clones][:num_clones],
          "uniques"   => dm[:clones][:num_unique_cloners],
        }
      end
    }
  end

  def insights_client_traffic_clones_weekly_hash(insights_response, options = {})
    traffic_data = insights_response[:traffic_data]
    return { "count" => 0, "uniques" => 0, "clones" => [] } if traffic_data.nil?

    utc = Time.find_zone("UTC")
    {
      "count"   => traffic_data[:summary_14d][:clones][:num_clones],
      "uniques" => traffic_data[:summary_14d][:clones][:num_unique_cloners],
      "clones" => traffic_data[:weekly_metrics].map do |dm|
        {
          "timestamp" => utc.strptime(dm[:day], "%Y-%m-%d").iso8601,
          "count"     => dm[:clones][:num_clones],
          "uniques"   => dm[:clones][:num_unique_cloners],
        }
      end
    }
  end
end
