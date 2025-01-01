# typed: false
# frozen_string_literal: true

require "json"
require "octolytics/pond"

module Api::Serializer::TrafficDependency
  def traffic_referrers_hash(traffic_referrers, options = {})
    traffic_referrers.slice("referrer", "count", "uniques")
  end

  def traffic_contents_hash(traffic_contents, options = {})
    traffic_contents.slice("path", "title", "count", "uniques")
  end

  def traffic_views_hash(counts, options = {})
    counts.slice("count", "uniques").merge({
      "views" => counts["views"].map do |view|
        {
          "timestamp" => serialize_pond_timestamp(view["timestamp"]),
          "count"     => view["count"],
          "uniques"   => view["uniques"],
        }
      end,
    })
  end

  def traffic_clones_hash(counts, options = {})
    counts.slice("count", "uniques").merge({
      "clones" => counts["clones"].map do |clone|
        {
          "timestamp" => serialize_pond_timestamp(clone["timestamp"]),
          "count"     => clone["count"],
          "uniques"   => clone["uniques"],
        }
      end,
    })
  end

  def serialize_pond_timestamp(timestamp)
    Time.at(timestamp / 1000).getutc.iso8601
  rescue NoMethodError
    raise Api::Serializer::InvalidTimestampError.new("Invalid timestamp '#{timestamp}'")
  end
end
