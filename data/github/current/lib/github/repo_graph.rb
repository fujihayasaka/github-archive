# typed: true
# frozen_string_literal: true

require "time"
require "zlib"
require "github/cache_lock"

module GitHub
  module RepoGraph
    autoload :Cache, "github/repo_graph/cache"
    autoload :Cached, "github/repo_graph/cached"
    autoload :CodeFrequency, "github/repo_graph/code_frequency"
    autoload :CommitActivity, "github/repo_graph/commit_activity"
    autoload :Contributors, "github/repo_graph/contributors"
    autoload :Eventer, "github/repo_graph/eventer"
    autoload :ContributionInsights, "github/repo_graph/contribution_insights"
    autoload :Participation, "github/repo_graph/participation"
    autoload :PunchCard, "github/repo_graph/punch_card"

    GRAPH_NAMES = %w[punch-card code-frequency commit-activity contributors].freeze

    MIN_COMMITS_FOR_INDEXING = 10_000

    # Raised if calling code uses a bad graph type name
    class UnknownGraphError < StandardError
      def initialize(name)
        super("#{name} is an unknown type for building a graph")
      end
    end

    # Errors raised when the underlying repository being used to build
    # a graph is in a problematic state.
    class RepoGraphError < StandardError
      def initialize(repo, state)
        # We cannot report nwo here due to PII restrictions, so report owner login and repo id if available
        super("Can't build graph for owner #{repo&.owner&.login}, repo id #{repo.id.inspect}, repo is #{state}")
      end
    end

    # specific repo graph error classes
    class NewRepoError < RepoGraphError; end
    class InvalidRepoError < RepoGraphError; end
    class EmptyRepoError < RepoGraphError; end
    class UnusableDataError < RepoGraphError; end

    # Background job interface to update a repository graph. This is typically called
    # from within the RepositoryUpdateGraph job that gets enqueued when the
    # cache for a graph misses. Records timing information in graphite under
    # 'github.repo_graph.<graph-name>'.
    #
    # repo       - Repository record.
    # graph_name - Name of the graph as a String.
    #
    # Raises an Error for unknown graphs.
    # Returns nothing.
    def self.update(repo, graph_name)
      graph_class = class_for(graph_name)
      graph = cached(repo, graph_class)

      if graph.cached?
        return
      end

      GitHub.dogstats.time("repo_graph", tags: ["type:#{graph_name}"]) do
        graph.update!
      end
    end

    # Instantiate a new instance of the given graph class with the given repo
    # object and decorates it with RepoGraph::Cached which can determine when
    # to enqueue a background job and make sure there's only ever one graph for
    # a given repo being updated at the same time.
    #
    # repo  - Saved and valid Repository record. The associated git repo must
    #         exist and disk and not be empty.
    # klass - The graph Class object. It should respond to #name, #cache_key
    #         and #data. See RepoGraph::Cached object for details.
    #
    # Returns the a new RepoGraph::Cached instance.
    # Raises an Error for invalid repositories.
    def self.cached(repo, klass)
      raise NewRepoError.new(repo, "new") if repo.new_record?
      raise InvalidRepoError.new(repo, "invalid") if !repo.valid?
      raise EmptyRepoError.new(repo, "empty") if repo.empty?

      cache = Cache.new(repo, repo.network_id, repo.default_oid)

      graph = klass.new(repo, cache)
      Cached.new(graph, repo)
    end

    # Clear caches (both on disk and memcached) for a repository's graph to
    # force a rebuild.
    #
    # repo       - Repository object.
    # graph_name - Name of the graph as a String, e.g. "contributors".
    #
    # Returns nothing.
    def self.clear_cache(repo, graph_name)
      return if repo.nil?
      graph_class = class_for(graph_name)
      cached(repo, graph_class).clear
    rescue EmptyRepoError
      # nothing to clear out.
    end

    # Pull data from the cache for the given graph or enqueue a job to compute
    # and write the data to the cache.
    #
    # graph - The RepoGraph::Cached instance.
    #
    # Returns an abitrary graph data structure (typically an Array or a Hash)
    #   from the cache or nil when it's not cached.
    def self.cached_data_or_enqueue_job(graph, cache_only: false)
      if graph.cached?
        raise UnusableDataError.new(graph.repo, "without valid data") if graph.empty?
        graph.data
      else
        graph.update unless cache_only
        nil
      end
    end

    # Returns a class suitable for building the given graph.
    def self.class_for(graph_name)
      case graph_name
      when "punch-card"
        PunchCard
      when "code-frequency"
        CodeFrequency
      when "commit-activity"
        CommitActivity
      when "contributors"
        Contributors
      when "participation"
        Participation
      else
        raise UnknownGraphError.new(graph_name.inspect)
      end
    end

    # Punch Card - https://github.com/github/github/graphs/punch-card
    #
    # The data consists of an Array made of 168 tree-elements arrays with the
    # day of the week, hour of the day and number of commits, starting on
    # Sunday up to Saturday.
    #
    # Example:
    #
    #   [
    #     [0, 0, 18], // Sunday
    #     [0, 1, 3],
    #     ...,
    #     [0, 23, 0],
    #     ...,
    #     [1, 0, 15], // Monday
    #     ...,
    #     [6, 0, 21], // Saturday
    #   ]
    def self.punch_card_data(repo)
      cache = Cache.new(repo, repo.network_id, repo.default_oid)
      PunchCard.new(repo, cache).data
    end

    # Should CommitContributions table be used to index commit data for the repo?
    #
    # ContributionInsights will be used to index commit data if it is enabled, the caller
    # is not explicitly asking for cached data and the repository's history
    # is equal or more than MIN_COMMITS_FOR_INDEXING commits long
    def self.use_insights?(viewer:, repository:, cache_only:)
      return false if cache_only

      commit_count = repository.rpc.fast_commit_count(repository.default_oid, MIN_COMMITS_FOR_INDEXING, timeout: 2)
      GitHub.dogstats.increment "repographs.skip_eventer", tags: ["result:#{commit_count < MIN_COMMITS_FOR_INDEXING}"]
      commit_count >= MIN_COMMITS_FOR_INDEXING
    end

    # Code Frequency - https://github.com/github/github/graphs/code-frequency
    #
    # The data is an Array of three-elements Arrays with the beginning of the
    # week (epoch, oldest first), number of line additions, and, number of
    # nd deletions. It goes as far back in the history as possible but is
    # limited to 50,000 commits.
    #
    # Example:
    #
    #   [
    #     [1189288800, 613, -66]
    #     [1189893600, 184, -12],
    #     ...
    #   ]
    def self.code_frequency_data(repo, viewer: nil, cache_only: false)
      if use_insights?(viewer: viewer, repository: repo, cache_only: cache_only)
        # We're stretching the meaning of authenticated here to exclude users that are authenticated but marked
        # as spammy. It's not ideal, but it gives us some control over API abuses where several authenticated user
        # accounts are used to avoid rate limits. The effect of spammy users not being considered as authenticated
        # here is that they will be sent to the anonymous queue, which prevents them from flooding the authenticated
        # legit users one, degrading performance.
        authenticated = !viewer.nil? && !viewer.spammy?
        Repository::ContributionGraphStatus.for_repository(repo).code_frequency_data(authenticated: authenticated)
      else
        graph = cached(repo, CodeFrequency)
        cached_data_or_enqueue_job(graph, cache_only: cache_only)
      end
    end

    # Contributors - https://github.com/github/github/graphs/contributors
    #
    # The data is represented as an Array of Hashes representing an author and
    # their contributions from week to week over the lifetime of the project.
    #
    # { w: Unix timestamp at beginning of week, a: additions, d: deletions, c: commits }
    #
    # Example:
    #
    #    [
    #      {
    #        "author":"tmm1",
    #        "weeks": [
    #          {"w":"1367712000","a":0,"d":0,"c":0},
    #          {"w":"1368316800","a":0,"d":0,"c":0},
    #          ...
    def self.contributors_data(repo, viewer: nil, cache_only: false)
      if use_insights?(viewer: viewer, repository: repo, cache_only: cache_only)
        authenticated = !viewer.nil? && !viewer.spammy?
        Repository::ContributionGraphStatus.for_repository(repo).contributors_data(authenticated: authenticated)
      else
        graph = cached(repo, Contributors)
        cached_data_or_enqueue_job(graph, cache_only: cache_only)
      end
    end

    # Commit Activity - https://github.com/github/github/graphs/commit-activity
    #
    # The data is represented as an Array of Hashes representing one week.
    # Each week Hash includes the week in epoch time (most recent first),
    # an Array with the number of commits for each day and the total number
    # of commits for the week.
    #
    # Example:
    #
    #   [
    #     {"week"=>1189893600, "days"=>[2, 2, 2, 2, 2, 2, 2], "total"=>14},
    #     ...
    #   ]
    def self.commit_activity_data(repo, viewer: nil, cache_only: false)
      if use_insights?(viewer: viewer, repository: repo, cache_only: cache_only)
        authenticated = !viewer.nil? && !viewer.spammy?
        Repository::ContributionGraphStatus.for_repository(repo).commit_activity_data(authenticated: authenticated)
      else
        graph = cached(repo, CommitActivity)
        cached_data_or_enqueue_job(graph, cache_only: cache_only)
      end
    end

    # Participation - Blue and grey bars on user profiles & spark lines in repos list
    # repo - Repository to get participation for
    # cache_only - Returns data only if cached, otherwise returns nil and doesn't start any task
    def self.participation_data(repo, cache_only: false)
      Participation::Data.new(repo).fetch(cache_only:)
    end
  end
end
