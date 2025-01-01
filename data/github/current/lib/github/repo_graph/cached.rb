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
        @data ||= GitHub.cache.get(cache_key)
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
        @data = nil

        if cache_ttl
          GitHub.cache.set(cache_key, @graph.data, cache_ttl)
        else
          GitHub.cache.set(cache_key, @graph.data)
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
    end
  end
end
