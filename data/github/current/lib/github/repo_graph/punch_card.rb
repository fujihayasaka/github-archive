# typed: true
# frozen_string_literal: true

module GitHub
  module RepoGraph
    class PunchCard
      def initialize(repo, cache)
        @repo = repo
        @cache = cache
      end

      attr_reader :cache

      def name
        "punch-card"
      end

      def cache_key
        "%s:%s:%s" % [
          "v2",
          @repo.network_id,
          @repo.default_oid,
        ]
      end

      def empty?(check = data)
        check.map(&:last).uniq == [0]
      end

      def data
        data = {}

        0.upto(6) do |wday|
          data[wday] = {}
          0.upto(23) do |hour|
            data[wday][hour] = 0
          end
        end

        @cache.commit_times.each do |tuple|
          data[tuple.first][tuple.last] += 1
        end

        ret = []
        0.upto(6) do |wday|
          0.upto(23) do |hour|
            ret << [wday, hour, data[wday][hour]]
          end
        end
        ret
      end

      def self.empty_graph
        ret = []
        0.upto(6) do |wday|
          0.upto(23) do |hour|
            ret << [wday, hour, 0]
          end
        end
        ret
      end
    end
  end
end
