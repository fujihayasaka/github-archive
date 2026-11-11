# typed: true
# frozen_string_literal: true

module GitHub
  module Config
    module RepositoryInsights
      def repos_insights_enabled?(repo)
        FeatureFlag.vexi.enabled?(:repo_traffic_job, repo, default: false)
      end

      def repos_insights_url
        GitHub.environment.fetch("REPOS_INSIGHTS_URL", "http://localhost:28080/twirp")
      end

      sig { returns(::RepositoryInsights::Client) }
      def repos_insights_client
        @repos_insights_client ||= ::RepositoryInsights::Client.new
      end
    end
  end

  extend Config::RepositoryInsights
end
