# typed: true
# frozen_string_literal: true

module Stratocaster::Indexers
  class GlobalIndexer

    def self.create(options = {})
      new(options)
    end

    def size(key)
      Stratocaster::GlobalIndex.by_key(full_key(key)).count
    end

    attr_accessor :prefix
    # attr_reader :store

    def initialize(options = {})
      @prefix   = options[:prefix]   || :stratocaster
      @id_field = options[:id]       || :id
      @max      = options[:max]      || Stratocaster::DEFAULT_INDEX_SIZE
    end

    # Public
    def insert(*keys)
      if pipelining?
        full_keys = keys.flatten.map { |key| full_key(key) }
        Stratocaster::GlobalIndex.insert(full_keys, @current_id)
      else # not pipelining, lets fix that oversight
        with(keys.shift) { |indexer| indexer.insert(*keys) }
      end
    end

    # Public
    def purge(*keys)
      if pipelining?
        full_keys = keys.flatten.map { |key| full_key(key) }
        Stratocaster::GlobalIndex.purge(full_keys, @current_id)
        tags = full_keys.map { |k| "key:#{k}" }
        GitHub.dogstats.count("stratocaster_global_indexer.purge", full_keys.length, tags: tags)
      else
        with(keys.shift) { |indexer| indexer.purge(*keys) }
      end
    end

    # Public
    def with(record)
      @current_id = record.send(@id_field)
      yield self
    ensure
      @current_id = nil
    end

    # Public
    # Returns the set of event IDs for the real-time event feed.
    def ids(key)
      Stratocaster::GlobalIndex.values(full_key(key), @max, @min_time, @max_time)
    end

    # Public
    # Returns the set of event IDs for the delayed event feed.
    def drop(*keys)
      full_keys = keys.flatten.map { |key| full_key(key) }
      Stratocaster::GlobalIndex.clear_keys(full_keys)
      tags = full_keys.map { |k| "key:#{k}" }
      GitHub.dogstats.count("stratocaster_global_indexer.drop", full_keys.length, tags: tags)
    end

    # Public
    #
    # Indicates if this indexer is setup to handle batches received from
    # the Hydro consumer
    #
    def supports_hydro?
      false
    end

    # Public
    # Returns redis key for the real-time event feed.
    def full_key(key)
      "#{@prefix}:#{key}"
    end

    def pipelining?
      @current_id
    end
  end
end
