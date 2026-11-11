# typed: true
# frozen_string_literal: true

module GitHub
  module Config
    module RepositoryInsights
      def repos_insights_url
        GitHub.environment.fetch("REPOS_INSIGHTS_URL", "http://localhost:28080/twirp")
      end
    end
  end

  extend Config::RepositoryInsights
end
