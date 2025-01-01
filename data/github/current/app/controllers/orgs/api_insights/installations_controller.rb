# typed: strict
# frozen_string_literal: true

module Orgs
  module ApiInsights
    class InstallationsController < BaseController

      depends_on_clusters ApplicationRecord::Mysql1,
        ApplicationRecord::Configurations,
        ApplicationRecord::IamAbilities,
        ApplicationRecord::Collab,
        ApplicationRecord::Mysql2,
        ApplicationRecord::NotificationsEntries,
        ApplicationRecord::Billing,
        ApplicationRecord::Copilot,
        only: [:index]

      sig { void }
      def index
        render_react_app(
          title: "Api Insights",
          payload: {
            sidenav: sidenav,
            page_params: default_page_params(has_table_filters: false),
            breadcrumb: breadcrumb,
            installation_stats: installation_stats,
            time_stats: time_stats,
            time_filters: time_filters,
            requests_table: requests_table,
          },
          page_data: { selected_link: :insights },
          ssr: false, # disabled until guidance is updated to allow SSR
        )
      end

      private

      sig { returns(T::Hash[Symbol, T.untyped]) }
      def breadcrumb
        {
          api_insights_base_url: api_org_insights_path(this_organization, only_path: true),
          name: this_actor[:name],
        }
      end

      sig { returns(T::Hash[Symbol, T.untyped]) }
      def requests_table
        {
          title: "Routes",
          description: "View usage by individual API route",
          placeholder_text: "Search for a route",
          pagination_text: "Pagination for routes",
          variant: "routes",
          rows: 10.times.map { |i| generate_row(id: i) },
          page_size: 10,
          total_count: 20,
        }
      end

      sig { params(id: Integer).returns(T::Hash[Symbol, T.untyped]) }
      def generate_row(id:)
        {
          id: id,
          name: "#{%w[repositories users clouds puppies organizations].sample}/:id/#{%w[latest projects lists items].sample}",
          total_requests: round_to_human(rand(9999..99999)),
          rate_limited_requests: round_to_human(rand(99..999)),
          last_rate_limited: format_time_long(Time.current - rand(1..100).minutes),
          description: "Last used #{format_time_long(Time.current - rand(1..100).minutes)}"
        }
      end

      sig { returns(T::Hash[String, T.untyped]) }
      def installation_stats
        stats = {
          request_count: rand(99999...183337),
          rate_limited_request_count: rand(99...90000),
          current_limit: this_actor[:rate_limit]
        }
        stats.transform_values { |v| round_to_human(v) }
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

      sig { returns(T::Hash[Symbol, T.untyped]) }
      memoize def this_actor
        {
          name: ["Slack + GitHub", "Travis CI", "GitGuardian", "Zenhub", "Synk", "SonarCloud", "WakaTime", "Azure Boards"].sample,
          type: "installation", # GitHub App representing itself
          rate_limit: 15_000,
        }
      end
    end
  end
end
