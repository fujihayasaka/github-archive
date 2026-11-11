# typed: true
# frozen_string_literal: true

module GitHub
  module RepoGraph
    # Drop-in replacement for RepoGraph::Cached that stores graph payloads in Cosmos
    # via the repos-insights Twirp service instead of memcache. Mirrors the public
    # surface of Cached so RepositoryUpdateGraphJob can drive it the same way.
    class CosmosCached
      def initialize(graph, repo)
        @graph = graph
        @repo = repo
      end

      attr_reader :repo

      def cached?
        !data.nil?
      end

      # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
      def data
        return @data if instance_variable_defined?(:@data)

        @data = read_from_cosmos
        log_cache_event(function: "data", action: "read", hit: !@data.nil?)
        @data
      end
      # rubocop:enable GitHub/ControllersShouldUseMemoizeForMemoization

      def empty?
        @graph.empty?(data)
      end

      def update
        RepositoryUpdateGraphJob.perform_later(@repo.id, @graph.name, GitHub.cache.skip)
      end

      def update!
        @data = @graph.data
        write_to_cosmos(@data)
        log_cache_event(function: "update!", action: "write", ttl: cache_ttl, data: @data)
      end

      # Cosmos entries are scoped to network_id + default_oid and expire via TTL,
      # so there is nothing to actively invalidate here. We still clear the on-disk
      # git graph cache to mirror the memcache-backed Cached behavior.
      def clear
        remove_instance_variable(:@data) if instance_variable_defined?(:@data)
        @graph.cache.clear
      end

      def cache_key
        @graph.cache_key
      end

      def cache_ttl
        if @graph.respond_to?(:cache_ttl)
          @graph.cache_ttl
        end
      end

      private

      def read_from_cosmos
        @graph.read_from_cosmos
      rescue RepositoryInsights::TwirpError, Faraday::Error => e
        GitHub.dogstats.increment("repo_graph.cosmos_read.error", tags: ["type:#{@graph.name}"])
        Failbot.report(e, app: "github", "gh.repo.id": @repo.id, "gh.repo.graph_name": @graph.name)
        nil
      end

      def write_to_cosmos(data)
        return if data.nil?

        @graph.write_to_cosmos(data)
      rescue RepositoryInsights::TwirpError, Faraday::Error => e
        GitHub.dogstats.increment("repo_graph.cosmos_write.error", tags: ["type:#{@graph.name}"])
        Failbot.report(e, app: "github", "gh.repo.id": @repo.id, "gh.repo.graph_name": @graph.name)
      end

      def log_cache_event(function:, action:, hit: nil, ttl: nil, data: nil)
        return unless FeatureFlag.vexi.enabled?(:repo_graph_cache_debug_logging, @repo, default: false)

        context = {
          "code.namespace": "GitHub::RepoGraph::CosmosCached",
          "code.function": function,
          "gh.repo.id": @repo.id,
          "gh.repo.default_oid": @repo.default_oid,
          "gh.repo.graph_name": @graph.name,
          "gh.repo.graph_cache_key": @graph.cache_key,
          "gh.infra.site": GitHub.server_site,
          "gh.repo.graph_cache.action": action,
        }
        context["gh.repo.graph_cache.hit"] = hit unless hit.nil?
        context["gh.repo.graph_cache.ttl"] = ttl unless ttl.nil?
        context["gh.repo.graph_cache.data_length"] = data.length unless data.nil?
        context["gh.repo.graph_cache.data_nil"] = data.nil?

        GitHub.logger.info("Repo graph cache event", context)
      end
    end
  end
end
