# typed: strict
# frozen_string_literal: true

module Orgs
  module ApiInsights
    class SummaryController < BaseController

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
            page_params: default_page_params,
            summary_stats: summary_stats,
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
      def requests_table
        {
          title: "Actors",
          description: "View usage by individual app or users",
          placeholder_text: "Search for an app or user",
          pagination_text: "Pagination for actors",
          filters: table_filters,
          rows: 10.times.map { |i| generate_row(id: i) },
          page_size: 10,
          total_count: 100,
        }
      end

      sig { params(id: Integer).returns(T::Hash[Symbol, T.untyped]) }
      def generate_row(id:)
        if [true, false].sample
          first = %w[Wade Karissa Greta Hernan Ramsey Ashe].sample
          last = %w[Hudson Fitch Hess McCutcheon Ramon Hill].sample
          return {
            id: id,
            name: "#{first} #{last}",
            total_requests: round_to_human(rand(9999..99999)),
            rate_limited_requests: round_to_human(rand(99..999)),
            last_rate_limited: format_time_long(Time.current - rand(1..100).minutes),
            description: "@#{first}#{last}",
            href: users_api_org_insights_path(org: this_organization, user: current_user, only_path: true),
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
          href: installations_api_org_insights_path(org: this_organization, installation_id: rand(1..9999), only_path: true),
          icon_url: current_user&.primary_avatar_url,
          square_icon: true
        }
      end

      sig { returns(T::Hash[String, T.untyped]) }
      def summary_stats
        stats = {
          request_count: rand(99999...183337),
          rate_limited_request_count: rand(99...90000)
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
    end
  end
end
