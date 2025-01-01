# typed: true
# frozen_string_literal: true

module Stratocaster::Indexers
  class NullIndexer
    def initialize(hash = nil, options = nil)
    end

    def insert(*keys)
    end

    def purge(*keys)
    end

    def ids(key)
      []
    end

    def drop(*keys)
    end

    def with(record)
      yield self
    end

    def clear
    end

    # Public
    #
    # Indicates if this indexer is setup to handle batches received from
    # the Hydro consumer
    #
    def supports_hydro?
      false
    end
  end
end
