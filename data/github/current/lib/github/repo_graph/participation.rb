# typed: true
# frozen_string_literal: true

module GitHub
  module RepoGraph
    class Participation
      class Data
        def initialize(repository)
          @repository = repository
        end

        attr_reader :repository

        def fetch(time: Time.now, cache_only: false)
          midnight = time.utc.midnight
          key = cache_key(midnight)

          if cache_only
            GitHub.cache.get(key)
          else
            GitHub.cache.fetch(key) { fetch!(time: midnight) }
          end
        end

        def fetch!(time:)
          return GitHub::RepoGraph::Participation::Data.empty_graph unless repository&.default_oid

          user = repository.user
          emails = user.emails.map { |x| x.email }

          repository.rpc.participation_stats(repository.default_oid, emails, time)
        end

        def self.empty_graph
          { "all" => [], "owner" => [] }
        end

        private

        def cache_key(time)
          suffix = Digest::SHA256.hexdigest("GitHub::Graphs::Participation:v5:#{@repository.id}:#{time.to_i}")
          "participation-graph:#{suffix}"
        end
      end
    end
  end
end
