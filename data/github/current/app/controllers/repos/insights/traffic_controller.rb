# typed: strict
# frozen_string_literal: true

class Repos::Insights::TrafficController < GitContentController
  before_action :enforce_plan_supports_insights
  before_action :pushers_only
  before_action :ensure_flag_enabled
  layout "repository"

  sig { returns(String) }
  def self.react_bundle_name
    "repos-traffic"
  end

  stylesheet_bundle :insights

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Spokes,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Memex,
    only: [:index]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Spokes,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    only: [:traffic_data, :popular_content_data, :referring_sites_data, :referring_paths_data]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index],
    optional: true

  # Maximum number of items to return in table data
  MAX_TABLE_ITEMS = 10

  sig { void }
  def index # rubocop:todo GitHub/UseRestfulActions
    payload = IndexRoutePayload.new(graph_data_path: new_traffic_data_path)
    respond_with_react(
      payload: payload,
      title: "Traffic · #{current_repository.name_with_display_owner}",
      layout: "layouts/repository/react_insights"
    )
  end

  sig { void }
  def traffic_data # rubocop:todo GitHub/UseRestfulActions
    begin
      query_params = { from: time_range.first.to_i * 1000, to: time_range.last.to_i * 1000 }

      response = GitHub.pond_client.counts(
        current_repository.id,
        Pond::EventType::VIEW,
        Pond::Granularity::DAY,
        query_params)
      render json: Pond.format_time_series(
        data: response.data["data"],
        from: time_range.first,
        to: time_range.last,
        event_type: Pond::EventType::VIEW
      )
    rescue Octolytics::ClientError, Octolytics::ServerError => e
      Failbot.report!(e)
      render json: { error: "Unable to fetch traffic data" }, status: :service_unavailable
    end
  end

  sig { void }
  def clone_activity_data # rubocop:todo GitHub/UseRestfulActions
    begin
      query_params = { from: time_range.first.to_i * 1000, to: time_range.last.to_i * 1000 }

      response = GitHub.pond_client.counts(
        current_repository.id,
        Pond::EventType::CLONE,
        Pond::Granularity::DAY,
        query_params)
      render json: Pond.format_time_series(
        data: response.data["data"],
        from: time_range.first,
        to: time_range.last,
        event_type: Pond::EventType::CLONE
      )
    rescue Octolytics::ClientError, Octolytics::ServerError => e
      Failbot.report!(e)
      render json: { error: "Unable to fetch clone activity data" }, status: :service_unavailable
    end
  end

  sig { void }
  def popular_content_data # rubocop:todo GitHub/UseRestfulActions
    begin
      response = GitHub.pond_client.content(current_repository.id)
      # Limit to first MAX_TABLE_ITEMS items
      data = response.data["data"]
      limited_data = data.is_a?(Array) ? data.first(MAX_TABLE_ITEMS) : data

      render json: cleaned_content(limited_data)
    rescue Octolytics::ClientError, Octolytics::ServerError => e
      Failbot.report!(e)
      render json: { error: "Unable to fetch popular content data" }, status: :service_unavailable
    end
  end

  sig { void }
  def referring_sites_data # rubocop:todo GitHub/UseRestfulActions
    begin
      response = GitHub.pond_client.referrers(
        current_repository.id,
        { from: time_range.first.to_i * 1000, to: time_range.last.to_i * 1000 })
      # Limit to first MAX_TABLE_ITEMS items
      data = response.data["data"]
      limited_data = data.is_a?(Array) ? data.first(MAX_TABLE_ITEMS) : data
      limited_data.each do |item|
        item["referrer_paths_allowed"] = !should_not_link_to_paths?(item["referrer"])
      end
      render json: limited_data
    rescue Octolytics::ClientError, Octolytics::ServerError => e
      Failbot.report!(e)
      render json: { error: "Unable to fetch referring sites data" }, status: :service_unavailable
    end
  end

  sig { void }
  def referring_paths_data # rubocop:todo GitHub/UseRestfulActions
    # Require a referrer domain
    referrer_domain = params[:referrer]
    unless referrer_domain.present?
      render json: { error: "Missing referrer parameter" }, status: :bad_request
      return
    end

    begin
      response = GitHub.pond_client.referrer_paths(
        current_repository.id,
        referrer_domain,
        { from: time_range.first.to_i * 1000, to: time_range.last.to_i * 1000 })
      data = response.data["data"]
      limited_data = data.is_a?(Array) ? data.first(MAX_TABLE_ITEMS) : data
      render json: limited_data
    rescue Octolytics::ClientError, Octolytics::ServerError => e
      Failbot.report!(e)
      render json: { error: "Unable to fetch referring paths data" }, status: :service_unavailable
    end
  end

  private

  sig { params(referrer: String).returns(T::Boolean) }
  def should_not_link_to_paths?(referrer)
    # Don't link to GitHub paths
    return true if /github\.com\z/i.match?(referrer)

    # Don't link to search engine paths
    search_engine_domains = %w[
      Google
      Yahoo
      Bing
      Search
      Ask
      DuckDuckGo
      StartPage
      AOL
      Baidu
    ]
    search_engine_domains.any? { |domain| referrer.downcase.include?(domain.downcase) }
  end

  class IndexRoutePayload < ReactPayload::Base
    sig { override.returns(String) }
    def route_id
      "trafficRoute"
    end

    sig { params(graph_data_path: String).void }
    def initialize(graph_data_path:)
      @graph_data_path = graph_data_path
    end

    sig do
      override.returns(T::Hash[String, T.untyped])
    end
    def payload
      {
        "graphDataPath" => @graph_data_path,
      }
    end
  end

  sig { params(graph_name: String).void }
  def handle_skipmc_for(graph_name)
    if GitHub.cache.skip
      GitHub::RepoGraph.clear_cache(current_repository, graph_name)
    end
  end

  sig { returns(T::Range[Time]) }
  def time_range
    # Return a 14-day range ending at the current time
    (Time.now.utc - 13.days).beginning_of_day..Time.now.utc.end_of_day
  end

  sig { void }
  def ensure_flag_enabled
    if (
      !current_repository.feature_flag_enabled?(:repos_react_traffic_charts, default: false) &&
      !current_user&.feature_flag_enabled?(:repos_react_traffic_charts, default: false)
    )
      render_404
    end
  end

  # Remove redundant information from content titles
  sig { params(content: T::Array[T::Hash[String, T.untyped]]).returns(T::Array[T::Hash[String, T.untyped]]) }
  def cleaned_content(content)
    nwo = Rails.env.development? ? "twbs/bootstrap" : current_repository.name_with_display_owner
    clean_regex = /( · #{Regexp.escape(nwo)})?( Wiki)?( · GitHub)?\z/

    content.map do |item|
      item["title"]&.gsub!(clean_regex, "")
      item
    end
  end
end
