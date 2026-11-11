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
        RepositoryInsights::Twirp.insights_client.get_repo_traffic_data(repo.id)
      end

      # return hash for now, will return the raw type in the future since the new cache supports it
      response.to_h
    rescue RepositoryInsights::Twirp::Error => error
      raise RepositoryInsights::TwirpError, error.message
    end

    # Fetch a cached contributors payload from the Repository Insights service.
    # Returns nil on cache miss; callers should recompute and call write_contributors.
    sig { params(repo: Repository).returns(T.nilable(T::Array[T::Hash[String, T.untyped]])) }
    def read_contributors(repo)
      response = RepositoryInsights::Twirp.insights_client.get_repo_contributors(
        network_id: repo.network_id.to_s,
        default_oid: repo.default_oid.to_s,
      )

      json = response.contributors_json
      cache_hit = !json.empty?

      GitHub.logger.info(
        "read_contributors",
        "gh.repo.id": repo.id,
        "gh.network.id": repo.network_id,
        "gh.repo.default_oid": repo.default_oid,
        "gh.repo.contributors_json_bytesize": json.to_s.bytesize,
        "cache_hit": cache_hit,
      )

      return nil unless cache_hit

      JSON.parse(json)
    rescue RepositoryInsights::Twirp::Error => error
      raise RepositoryInsights::TwirpError, error.message
    end

    # Write a contributors payload to the Repository Insights service, keyed by
    # network_id and default_oid.
    sig { params(repo: Repository, contributors_data: T::Array[T::Hash[String, T.untyped]]).void }
    def write_contributors(repo, contributors_data)
      contributors_json = JSON.generate(contributors_data)

      RepositoryInsights::Twirp.insights_client.create_repo_contributors(
        network_id: repo.network_id.to_s,
        default_oid: repo.default_oid.to_s,
        contributors_json: contributors_json,
      )

      GitHub.logger.info(
        "write_contributors",
        "gh.repo.id": repo.id,
        "gh.network.id": repo.network_id,
        "gh.repo.default_oid": repo.default_oid,
        "gh.repo.contributors_json_bytesize": contributors_json.bytesize,
      )
    rescue RepositoryInsights::Twirp::Error => error
      raise RepositoryInsights::TwirpError, error.message
    end

    # Fetch a cached commit activity payload from the Repository Insights service.
    # Returns nil on cache miss; callers should recompute and call write_commit_activity.
    sig { params(repo: Repository, cache_date: String).returns(T.nilable(T::Array[T::Hash[String, T.untyped]])) }
    def read_commit_activity(repo, cache_date:)
      response = RepositoryInsights::Twirp.insights_client.get_repo_commit_activity(
        network_id: repo.network_id.to_s,
        default_oid: repo.default_oid.to_s,
        cache_date: cache_date,
      )

      json = response.commit_activity_json
      cache_hit = !json.empty?

      GitHub.logger.info(
        "read_commit_activity",
        "gh.repo.id": repo.id,
        "gh.network.id": repo.network_id,
        "gh.repo.default_oid": repo.default_oid,
        "gh.repo.cache_date": cache_date,
        "gh.repo.commit_activity_json_bytesize": json.to_s.bytesize,
        "cache_hit": cache_hit,
      )

      return nil unless cache_hit

      JSON.parse(json)
    rescue RepositoryInsights::Twirp::Error => error
      raise RepositoryInsights::TwirpError, error.message
    end

    # Write a commit activity payload to the Repository Insights service, keyed by
    # network_id and default_oid.
    sig { params(repo: Repository, commit_activity_data: T::Array[T::Hash[String, T.untyped]], cache_date: String).void }
    def write_commit_activity(repo, commit_activity_data, cache_date:)
      commit_activity_json = JSON.generate(commit_activity_data)

      RepositoryInsights::Twirp.insights_client.create_repo_commit_activity(
        network_id: repo.network_id.to_s,
        default_oid: repo.default_oid.to_s,
        commit_activity_json: commit_activity_json,
        cache_date: cache_date,
      )

      GitHub.logger.info(
        "write_commit_activity",
        "gh.repo.id": repo.id,
        "gh.network.id": repo.network_id,
        "gh.repo.default_oid": repo.default_oid,
        "gh.repo.cache_date": cache_date,
        "gh.repo.commit_activity_json_bytesize": commit_activity_json.bytesize,
      )
    rescue RepositoryInsights::Twirp::Error => error
      raise RepositoryInsights::TwirpError, error.message
    end
  end
end
