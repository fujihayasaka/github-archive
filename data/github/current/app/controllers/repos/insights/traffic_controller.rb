# typed: strict
# frozen_string_literal: true

class Repos::Insights::TrafficController < GitContentController
  before_action :enforce_plan_supports_insights

  # this redirects to the home page if the user can't push, so only use it for the index method
  before_action :pushers_only, only: [:index]

  # this returns an empty 404, so use it for JSON endpoints
  before_action :ensure_traffic_enabled_and_repo_pushable, except: [:index]

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
    ApplicationRecord::Memex,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    only: [:data]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index],
    optional: true

  # Maximum number of items to return in table data
  MAX_TABLE_ITEMS = 10

  sig { void }
  def index
    payload = IndexRoutePayload.new
    respond_with_react(
      payload: payload,
      title: "Traffic · #{current_repository.name_with_display_owner}",
      layout: "layouts/repository/react_insights",
      page_data: {
        selected_link: :repo_graphs,
      },
    )
  end

  sig { void }
  def data # rubocop:todo GitHub/UseRestfulActions
    begin
      insights_response = RepositoryInsights.domain.traffic_for_repo(current_repository)
      if (traffic_data = insights_response&.dig(:traffic_data))
        views_data = format_traffic_time_series(traffic_data, :view)
        clones_data = format_traffic_time_series(traffic_data, :clone)
        top_content = traffic_data[:top_content].first(MAX_TABLE_ITEMS).map do |item|
          {
            "path" => item[:path],
            "title" => item[:title],
            "count" => item[:num_page_views],
            "uniques" => item[:num_unique_viewers],
          }
        end

        top_referrers = traffic_data[:top_referrers].first(MAX_TABLE_ITEMS).map do |item|
          paths_allowed = traffic_data[:top_referrer_paths].any? { |path_item| path_item[:referrer] == item[:referrer] }

          {
            "referrer" => item[:referrer],
            "count" => item[:num_page_views],
            "uniques" => item[:num_unique_viewers],
            "referrer_paths_allowed" => paths_allowed,
          }
        end

        top_referrer_paths = traffic_data[:top_referrer_paths].first(MAX_TABLE_ITEMS).map do |item|
          {
            "referrer" => item[:referrer],
            "full_url" => item[:full_url],
            "count" => item[:num_page_views],
            "uniques" => item[:num_unique_viewers],
          }
        end

        render json: {
          "views" => views_data,
          "clones" => clones_data,
          "top_content" => cleaned_content(top_content),
          "top_referrers" => top_referrers,
          "top_referrer_paths" => top_referrer_paths,
        }
      else
        render json: { error: "Traffic data is temporarily unavailable, please try again" }, status: :service_unavailable
      end
    rescue RepositoryInsights::TwirpError => e
      Failbot.report!(e)
      render json: { error: "Traffic data is temporarily unavailable, please try again" }, status: :service_unavailable
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

    sig do
      override.returns(T::Hash[String, T.untyped])
    end
    def payload
      {}
    end
  end

  sig { returns(T::Range[Time]) }
  def time_range
    # Return a 14-day range ending at the current time
    (Time.now.utc - 13.days).beginning_of_day..Time.now.utc.end_of_day
  end

  # Remove redundant information from content titles
  sig { params(content: T::Array[T::Hash[String, T.untyped]]).returns(T::Array[T::Hash[String, T.untyped]]) }
  def cleaned_content(content)
    nwo = Rails.env.development? ? "twbs/bootstrap" : current_repository.name_with_display_owner
    clean_regex = /( · #{Regexp.escape(nwo)})?( Wiki)?( · GitHub)?\z/

    content.map do |item|
      item["title"] = item["title"]&.gsub(clean_regex, "")
      item
    end
  end

  sig { void }
  def ensure_traffic_enabled_and_repo_pushable
    head 404 unless GitHub.traffic_graphs_enabled?
    head 404 unless current_user_can_push?
  end

  # convert repos_insights data to time series format:
  #   { "counts" => [{ "bucket" => unix_timestamp, "total" => X, "unique" => Y }, ...],
  #     "summary" => { "total" => X, "unique" => Y } }
  sig { params(traffic_data: T.untyped, event_type: Symbol).returns(T::Hash[String, T.untyped]) }
  def format_traffic_time_series(traffic_data, event_type)
    if event_type == :view
      total_count = traffic_data.dig(:summary_14d, :page_views, :num_page_views) || 0
      total_unique = traffic_data.dig(:summary_14d, :page_views, :num_unique_viewers) || 0
    else # CLONE
      total_count = traffic_data.dig(:summary_14d, :clones, :num_clones) || 0
      total_unique = traffic_data.dig(:summary_14d, :clones, :num_unique_cloners) || 0
    end

    counts = traffic_data[:daily_metrics].map do |metric|
      bucket = Time.parse(metric[:day]).to_i

      if event_type == :view
        count = metric.dig(:page_views, :num_page_views) || 0
        unique = metric.dig(:page_views, :num_unique_viewers) || 0
      else # CLONE
        count = metric.dig(:clones, :num_clones) || 0
        unique = metric.dig(:clones, :num_unique_cloners) || 0
      end

      {
        "bucket" => bucket,
        "total" => count,
        "unique" => unique,
      }
    end

    {
      "counts" => counts.reverse, # UI expects newest first
      "summary" => {
        "total" => total_count,
        "unique" => total_unique,
      }
    }
  end
end
