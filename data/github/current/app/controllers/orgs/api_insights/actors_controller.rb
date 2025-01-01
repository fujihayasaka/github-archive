# typed: strict
# frozen_string_literal: true

module Orgs
  module ApiInsights
    class ActorsController < BaseController

      depends_on_clusters ApplicationRecord::Mysql1,
        ApplicationRecord::Configurations,
        ApplicationRecord::IamAbilities,
        ApplicationRecord::Collab,
        ApplicationRecord::Mysql2,
        ApplicationRecord::NotificationsEntries,
        ApplicationRecord::Billing,
        ApplicationRecord::Copilot,
        only: [:index]

      before_action :require_this_user
      before_action :enforce_actor_types

      ACTOR_TYPES = T.let(%w[oauth_app classic_pat fine_grained_pat github_app_user_to_server].freeze, T::Array[String])

      sig { void }
      def index
        render_react_app(
          title: "Api Insights",
          payload: {
            sidenav: sidenav,
            page_params: default_page_params(has_table_filters: false),
            breadcrumb: breadcrumb,
            actor_stats: actor_stats,
            time_stats: time_stats,
            time_filters: time_filters,
            requests_table: requests_table,
          },
          page_data: { selected_link: :insights },
          ssr: false, # disabled until guidance is updated to allow SSR
        )
      end

      private

      sig { returns String }
      def label
        case params[:actor_type]
        when "oauth_app"
          "OAuth Apps"
        when "classic_pat"
          "Personal Access Tokens (Classic)"
        when "fine_grained_pat"
          "Fine-grained token"
        else
          "GitHub Apps"
        end
      end

      sig { returns(T::Hash[Symbol, T.untyped]) }
      def breadcrumb
        actor_name = "#{%w[SAML eng personal walrus project orgs auth].sample} token"
        if params[:actor_type] == "oauth_app" || params[:actor_type] == "github_app_user_to_server"
          actor_name = "#{%w[Red Green Purple Pineapple Strawberry Apple Banana Grape Walrus].sample} #{%w[Inc Co].sample}"
        end
        {
          api_insights_base_url: api_org_insights_path(this_organization, only_path: true),
          username: T.must(this_user).display_login,
          actor_name: actor_name,
          label: label
        }
      end

      sig { returns(T::Hash[Symbol, T.untyped]) }
      def requests_table
        {
          title: "Actors",
          description: "View usage by individual app or users",
          placeholder_text: "Search for an app or user",
          pagination_text: "Pagination for actors",
          filters: table_filters,
          rows: 10.times.map { |i| generate_row(id: i) },
          page_size: 10,
          total_count: 20,
        }
      end

      sig { params(id: Integer).returns(T::Hash[Symbol, T.untyped]) }
      def generate_row(id:)
        if [true, false].sample
          description = %w[SAML eng personal walrus project orgs auth].sample
          return {
            id: id,
            name: "#{description} token",
            total_requests: round_to_human(rand(9999..99999)),
            rate_limited_requests: round_to_human(rand(99..999)),
            last_rate_limited: format_time_long(Time.current - rand(1..100).minutes),
            description: "Personal access token (classic)",
            icon_url: current_user&.primary_avatar_url
          }
        end
        {
          id: id,
          name: "#{%w[Red Green Purple Pineapple Strawberry Apple Banana Grape Walrus].sample} #{%w[Inc Co].sample}",
          total_requests: round_to_human(rand(9999..99999)),
          rate_limited_requests: round_to_human(rand(99..999)),
          last_rate_limited: format_time_long(Time.current - rand(1..100).minutes),
          description: "GitHub App",
          icon_url: current_user&.primary_avatar_url,
          square_icon: true
        }
      end

      sig { returns(T::Hash[String, T.untyped]) }
      def actor_stats
        this_app = rand(10...80)
        stats = {
          request_count: round_to_human(rand(99999...183337)),
          rate_limited_request_count: round_to_human(rand(99...90000)),
          current_limit: round_to_human(5000),
          legend: ["This app", "Other apps"],
          breakdown: [this_app, 100 - this_app],
        }
      end

      sig { returns(T::Hash[Symbol, T.untyped]) }
      def time_stats
        now = Time.now
        start = now - selected_look_back_seconds
        interval = selected_bucket_seconds
        points = selected_look_back_seconds / interval

        stats = points.times.map { |i| { timestamp: (start + (i * selected_bucket_seconds)).to_i * 1000, request_count: rand(120...999999), rate_limited_request_count: rand(120...99999) } }

        time_stats = { request_count: [], rate_limited_request_count: [] }
        stats.each do |s|
          time_stats[:request_count] << [s[:timestamp], s[:request_count]]
          time_stats[:rate_limited_request_count] << [s[:timestamp], s[:rate_limited_request_count]]
        end

        time_stats
      end

      sig { returns(T.nilable(User)) }
      memoize def this_user
        User.find_by_login(params[:user])
      end

      sig { void }
      def require_this_user
        render_404 unless this_user
      end

      sig { void }
      def enforce_actor_types
        render_404 unless params[:actor_type].in?(ACTOR_TYPES)
      end
    end
  end
end
