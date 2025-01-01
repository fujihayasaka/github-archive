# typed: true
# frozen_string_literal: true

module Stratocaster::Indexers
  class MemoryIndexer
    attr_reader :storage

    def initialize(storage = nil, options = {})
      @max      = options[:max] || Stratocaster::DEFAULT_INDEX_SIZE
      @id_field = options[:id] || :id
      @storage  = storage || {}
    end

    def insert(*keys)
      if pipelining?
        keys.each do |key|
          (@storage[key.to_s] ||= []).unshift @current_id
        end
      else
        with(keys.shift) { |pipe| pipe.insert(*keys) }
      end
    end

    def bulk_insert(updates)
      @storage.merge!(updates)
    end

    def purge(*keys)
      if pipelining?
        keys.each do |key|
          next unless arr = @storage[key.to_s]
          arr.delete(@current_id)
        end
      else
        with(keys.shift) { |pipe| pipe.append(*keys) }
      end
    end

    def with(record)
      @current_id = record.send(@id_field)
      yield self
    ensure
      @current_id = nil
    end

    def ids(key)
      Array(@storage[key.to_s])[0, @max]
    end

    def drop(*keys)
      keys.each do |key|
        @storage.delete key.to_s
      end
    end

    def clear
      @storage = {}
    end

    def pipelining?
      @current_id
    end

    # Public
    #
    # Indicates if this indexer is setup to handle batches received from
    # the Hydro consumer
    #
    def supports_hydro?
      true
    end
  end
end
