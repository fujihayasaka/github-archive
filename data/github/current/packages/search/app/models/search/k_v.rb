# typed: strict
# frozen_string_literal: true

require_relative "k_v/data_store"

module Search
  class KV
    OWNER = "github/es-index-management"

    @kv = T.let(nil, T.nilable(GitHub::KV))

    sig { returns(GitHub::KV) }
    def self.store
      return @kv if @kv

      config = GitHub::KV.config.dup
      config.table_name = Search::KV::DataStore.table_name

      @kv = GitHub::KV.new(config: config) { ApplicationRecord::Domain::Search.connection }
    end
  end
end
