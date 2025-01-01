# typed: true
# frozen_string_literal: true

module Stratocaster::Indexers
  class DelayedGlobalIndexer < GlobalIndexer
    def initialize(options = {})
      super(options)
      @max_time = options[:max_time] || 10.minutes
      @min_time = options[:min_time] || 5.minutes
    end

    # Public
    # Returns redis key for the real-time event feed.
    def full_key(key)
      "#{@prefix}_sorted_set:#{key}"
    end

    # Public
    # This differes from the GlobalIndexer insert in that it
    # - throttles
    # - does not prune
    # Pruning will be done by pt-archiver (https://github.com/github/puppet/pull/23867)
    def insert(*keys)
      if pipelining?
        full_keys = keys.flatten.map { |key| full_key(key) }
        Stratocaster::GlobalIndex.throttle do
          Stratocaster::GlobalIndex.insert(full_keys, @current_id)
        end
        tags = full_keys.map { |k| "key:#{k}" }
        GitHub.dogstats.count("stratocaster_global_indexer.insert", full_keys.length, tags: tags)
      else # not pipelining, lets fix that oversight
        with(keys.shift) { |indexer| indexer.insert(*keys) }
      end
    end
  end
end
