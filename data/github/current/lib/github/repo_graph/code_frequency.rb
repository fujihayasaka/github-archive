# typed: true
# frozen_string_literal: true

require "date"

module GitHub
  module RepoGraph
    class CodeFrequency
      def initialize(repo, cache)
        @repo = repo
        @cache = cache
      end

      attr_reader :cache

      def name
        "code-frequency"
      end

      def cache_key
        "%s:%s:%s:%s" % [
          "v5",
          Date.today.to_s,
          @repo.network_id,
          @repo.default_oid,
        ]
      end

      def empty?(check = data)
        check.empty?
      end

      def data
        data = []

        @cache.weeks.each do |time|
          stats = @cache.data.select { |e| e[1] == time }

          if stats && !stats.empty?
            additions = stats.sum { |s| s[2] }
            delitions = stats.sum { |s| s[3] }
          else
            additions, delitions = 0, 0
          end

          data << [time, additions, -delitions]
        end
        data
      end
    end
  end
end
