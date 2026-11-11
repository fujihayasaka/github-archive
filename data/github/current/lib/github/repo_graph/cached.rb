# typed: true
# frozen_string_literal: true

module GitHub
  module RepoGraph
    # Abstract the necessary boiler plate around calculating and then caching
    # data for the various repository graphs. This makes sure there's only
    # ever one job running for a given graph.
    class Cached
      def initialize(graph, repo)
        @graph = graph
        @repo = repo
      end

      attr_reader :repo

      def cached?
        !data.nil?
      end

      def data
        return @data if instance_variable_defined?(:@data)

        key = cache_key
        @data = GitHub.cache.get(key)
        log_cache_event(function: "data", action: "read", key:, hit: !@data.nil?)
        @data
      end

      def empty?
        @graph.empty?(data)
      end

      def update
        RepositoryUpdateGraphJob.perform_later(@repo.id, @graph.name, GitHub.cache.skip)
      end

      def clear
        GitHub.cache.delete(cache_key)
        @graph.cache.clear
      end

      def update!
        key = cache_key
        @data = @graph.data

        if cache_ttl
          GitHub.cache.set(key, @data, cache_ttl)
        else
          GitHub.cache.set(key, @data)
        end

        log_cache_event(function: "update!", action: "write", key:, ttl: cache_ttl, data: @data)
        if FeatureFlag.vexi.enabled?(:repo_graph_cache_debug_logging, @repo, default: false)
          verify = GitHub.cache.get(key)
          log_cache_event(function: "update!", action: "write_verify", key:, hit: !verify.nil?)
        end
      end

      def cache_key(suffix = nil)
        key = [
          "repo-graph",
          "v3",
          @graph.cache_key,
          suffix,
        ].compact.join(":")
        Digest::SHA256.hexdigest(key)
      end

      def cache_ttl
        if @graph.respond_to?(:cache_ttl)
          @graph.cache_ttl
        end
      end

      private

      def log_cache_event(function:, action:, key:, hit: nil, ttl: nil, data: nil)
        return unless FeatureFlag.vexi.enabled?(:repo_graph_cache_debug_logging, @repo, default: false)

        context = {
          "code.namespace": "GitHub::RepoGraph::Cached",
          "code.function": function,
          "gh.repo.id": @repo.id,
          "gh.repo.default_oid": @repo.default_oid,
          "gh.repo.graph_name": @graph.name,
          "gh.repo.graph_cache_key": @graph.cache_key,
          "gh.repo.graph_cache_digest": key,
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
