# typed: true
# frozen_string_literal: true

module Repositories
  module Graph
    class TrafficView
      attr_reader :referrer_domain

      def initialize(repo, user, referrer_domain)
        @repo = repo
        @user = user
        @referrer_domain = referrer_domain
      end

      def fetch_data
        return @data_fetched if defined?(@data_fetched)

        # No-op request to new service for load testing
        GitHub.hydro_aggregation_api_client.repo_top_content(
          repo_id: @repo.id,
          from: 2.weeks.ago,
        )
        GitHub.hydro_aggregation_api_client.repo_top_referrers(
          repo_id: @repo.id,
          from: 2.weeks.ago,
        )

        GitHub.dogstats.time "graph", tags: ["action:traffic", "type:content"] do
          response = GitHub.pond_client.content(@repo.id)
          @content = Pond.format_top_n(
            data: response.data["data"],
            top_n_type: Pond::TopNType::CONTENT,
          )

          response = GitHub.pond_client.referrers(@repo.id)
          @domains = Pond.format_top_n(
            data: response.data["data"],
            top_n_type: Pond::TopNType::REFERRERS,
          )
        end
        @data_fetched = true
      rescue Octolytics::Error => error
        Failbot.report!(error)
        @data_fetched = false
      end

      def data_present?
        @data_fetched && (@content["content"].any? || @domains["referrers"].any?)
      end

      # Remove redundant information from content titles
      def cleaned_content
        nwo = Rails.env.development? ? "twbs/bootstrap" : @repo.name_with_display_owner
        clean_regex = /( · #{Regexp.escape(nwo)})?( Wiki)?( · GitHub)?\z/

        @content["content"].take(10).map do |content|
          content["title"].gsub!(clean_regex, "")
          content
        end
      end

      def referrers
        fetch_data
        @domains["referrers"].take(10)
      end

      def show_referrer_paths?
        @referrer_domain.present?
      end

      def paths_data
        return @paths_data if defined?(@paths_data)

        @paths_data = begin
          GitHub.dogstats.time "graph", tags: ["action:traffic", "type:referrer_paths"] do
            response = GitHub.pond_client.referrer_paths(@repo.id, @referrer_domain)
            Pond.format_top_n(
              data: response.data["data"],
              top_n_type: Pond::TopNType::REFERRER_PATHS,
              referrer: @referrer_domain,
            )
          end
        rescue Octolytics::Error => error
          Failbot.report!(error)
          nil
        end
      end

      def paths_data_present?
        paths_data.present?
      end

      def referrer_paths
        paths_data["paths"].take(10)
      end
    end
  end
end
