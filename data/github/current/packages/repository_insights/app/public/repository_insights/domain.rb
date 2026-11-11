# typed: strict
# frozen_string_literal: true

require "monolith-twirp-reposinsights-reposinsights"

module RepositoryInsights
  class Domain < GH::Domain::Base
    # Fetch traffic data for a repository, using caching to minimize calls to the Repository Insights service.
    sig { params(repo: Repository).returns(T.nilable(T::Hash[T.untyped, T.untyped])) }
    def traffic_for_repo(repo)
      client = RepositoryInsights::Cache::TrafficClient.new(repo)

      # propagate errors for now rather than handling them here, since that's how it currently works
      response = client.fetch(graceful_degradation: false) do
        RepositoryInsights::Twirp.traffic_client.get_repo_traffic_data(repo.id)
      end

      # return hash for now, will return the raw type in the future since the new cache supports it
      response.to_h
    rescue RepositoryInsights::Twirp::Error => error
      raise RepositoryInsights::TwirpError, error.message
    end
  end
end
