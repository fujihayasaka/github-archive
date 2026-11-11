# typed: true
# frozen_string_literal: true

# Comparator supports the safe comparison of hashes of cache clients. The comparator is initialized
# with a config type and the current hash of cache clients. The Comparator#compare method accepts
# a block expected to return an identical candidate hash of cache clients. Any mismatches will be logged.
# Any errors raised during resolving the candidate hash or comparison will be trapped and logged.
module GitHub
  module Cache
    class Config
      class Comparator
        include GitHub::Memoizer

        def initialize(config_type:, current:)
          @config_type = config_type
          @current = current
          @candidate = nil # set during comparison to trap errors
          @mismatches = Set.new
        end

        def compare
          @candidate = yield
          same_keys = same_keys?
          same_values = same_values?
          instrument_mismatches
          same_keys && same_values
        rescue StandardError => e
          instrument_error(e)
          false
        end

        private

        def same_keys?
          return true if @current.keys.sort == @candidate.keys.sort
          @mismatches.add(:keys)
          false
        end

        def same_values?
          same_values = @current.keys.map do |key|
            current_client = @current[key]
            candidate_client = @candidate[key]

            next false if candidate_client.nil?

            has_same_options = same_options?(current_client, candidate_client)
            has_same_servers = same_servers?(current_client, candidate_client)
            has_same_parition = same_partition?(current_client, candidate_client)
            has_same_options && has_same_servers && has_same_parition
          end
          same_values.all?
        end

        def same_options?(current_client, candidate_client)
          return true if current_client.options == candidate_client.options
          @mismatches.add(:options)
          false
        end

        def same_servers?(current_client, candidate_client)
          # order doesn't matter for servers
          return true if servers(current_client).sort == servers(candidate_client).sort
          @mismatches.add(:servers)
          false
        end

        def same_partition?(current_client, candidate_client)
          return true if current_client.current_partition == candidate_client.current_partition
          @mismatches.add(:current_partition)
          false
        end

        def servers(client)
          client.servers.map { |s| "#{s.hostname}:#{s.port}" }
        end

        def instrument_mismatches
          mismatches_tags = @mismatches.map { |m| "#{m}:true" }
          GitHub.dogstats.increment("github.cache.config.comparator",
            tags: [
              "config_type:#{@config_type}",
              "has_mismatches:#{@mismatches.any?}",
              *mismatches_tags
            ]
          )
        end

        def instrument_error(e)
          GitHub.dogstats.increment("github.cache.config.comparator",
            tags: [
              "config_type:#{@config_type}",
              "error:#{e.class.name}"
            ]
          )
        end
      end
    end
  end
end
